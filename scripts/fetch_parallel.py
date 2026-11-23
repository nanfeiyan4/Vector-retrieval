#!/usr/bin/env python3
"""Parallel HTTP range downloader (stdlib only, works on Windows and Linux).

Needed because ann-benchmarks.com throttles a single connection to ~0.3 MB/s in
CN networks: 525 MB would take ~28 min serially. With 24 range connections it
finishes in ~2 min, which makes the "fresh clone -> reproduce" path practical.

Usage:
    python3 fetch_parallel.py --url URL --out FILE [--connections 24]
                              [--chunk-mb 8] [--retries 5]

The output file is preallocated to Content-Length and each worker writes into
its own byte range via an independent file handle, so no locking is needed.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import queue
import sys
import threading
import time
import urllib.request

UA = {"User-Agent": "fetch_parallel/1.0"}


def head(url: str) -> tuple[int, dict]:
    req = urllib.request.Request(url, headers=UA, method="HEAD")
    with urllib.request.urlopen(req, timeout=30) as r:
        return int(r.headers["Content-Length"]), dict(r.headers)


def fetch_range(url: str, start: int, end: int, path: str, retries: int) -> None:
    last_err: Exception | None = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(
                url, headers={**UA, "Range": f"bytes={start}-{end}"}
            )
            with urllib.request.urlopen(req, timeout=60) as r:
                expected = end - start + 1
                buf = bytearray()
                while len(buf) < expected:
                    piece = r.read(min(1 << 20, expected - len(buf)))
                    if not piece:
                        break
                    buf += piece
                if len(buf) != expected:
                    raise IOError(f"short read {len(buf)}/{expected}")
                with open(path, "r+b") as f:
                    f.seek(start)
                    f.write(buf)
            return
        except Exception as exc:  # noqa: BLE001 - retry any transport error
            last_err = exc
            time.sleep(1.0 + attempt)
    raise RuntimeError(f"range {start}-{end} failed: {last_err}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--connections", type=int, default=24)
    ap.add_argument("--chunk-mb", type=int, default=8)
    ap.add_argument("--retries", type=int, default=5)
    ap.add_argument("--sha256", default="", help="expected sha256 (optional check)")
    args = ap.parse_args()

    size, headers = head(args.url)
    print(f"content-length: {size:,} bytes")
    for k in ("ETag", "Last-Modified", "Server"):
        if k in headers:
            print(f"{k}: {headers[k]}")
    if os.path.exists(args.out) and os.path.getsize(args.out) == size:
        print("already complete, skipping download")
    else:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
        with open(args.out, "wb") as f:
            f.truncate(size)
        chunk = args.chunk_mb << 20
        tasks: queue.Queue[tuple[int, int]] = queue.Queue()
        pos = 0
        while pos < size:
            tasks.put((pos, min(pos + chunk - 1, size - 1)))
            pos += chunk
        total_tasks = tasks.qsize()
        done = [0]
        lock = threading.Lock()
        t0 = time.time()

        def worker() -> None:
            while True:
                try:
                    start, end = tasks.get_nowait()
                except queue.Empty:
                    return
                fetch_range(args.url, start, end, args.out, args.retries)
                with lock:
                    done[0] += 1
                    pct = 100.0 * done[0] / total_tasks
                    if done[0] % 4 == 0 or done[0] == total_tasks:
                        rate = (done[0] * chunk) / max(1e-6, time.time() - t0) / 1e6
                        print(f"  {pct:5.1f}%  {done[0]}/{total_tasks}  ~{rate:.1f} MB/s", flush=True)

        threads = [threading.Thread(target=worker, daemon=True) for _ in range(args.connections)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

    got = os.path.getsize(args.out)
    if got != size:
        print(f"SIZE MISMATCH: {got} != {size}", file=sys.stderr)
        return 1

    h = hashlib.sha256()
    with open(args.out, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    digest = h.hexdigest()
    print(f"size: {got:,} bytes")
    print(f"sha256: {digest}")
    with open(args.out, "rb") as f:
        magic = f.read(8)
    print(f"magic: {magic!r} (expect b'\\x89HDF\\r\\n\\x1a\\n')")
    if args.sha256 and args.sha256.lower() != digest:
        print("SHA256 MISMATCH", file=sys.stderr)
        return 1
    print(f"elapsed: {time.time() - t0:.1f}s" if "t0" in dir() else "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
