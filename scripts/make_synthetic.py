#!/usr/bin/env python3
"""Generate a synthetic vector dataset (fallback when SIFT1M is unavailable).

Writes base.f32 / query.f32 / gt.i32 in the same layout as prepare_data.py.
"""
import argparse
import os

import numpy as np


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=20000)
    ap.add_argument("--nq", type=int, default=200)
    ap.add_argument("--dim", type=int, default=128)
    ap.add_argument("--k", type=int, default=100)
    ap.add_argument("--clusters", type=int, default=64)
    ap.add_argument("--outdir", default="/root/proj1/data/syn")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    rng = np.random.default_rng(2024)
    centers = rng.normal(size=(args.clusters, args.dim)).astype(np.float32)
    assign = rng.integers(0, args.clusters, size=args.n)
    base = centers[assign] + 0.15 * rng.normal(size=(args.n, args.dim)).astype(np.float32)
    qassign = rng.integers(0, args.clusters, size=args.nq)
    query = centers[qassign] + 0.15 * rng.normal(size=(args.nq, args.dim)).astype(np.float32)

    gt = np.zeros((args.nq, args.k), dtype=np.int32)
    for i in range(args.nq):
        d = ((base - query[i]) ** 2).sum(axis=1)
        gt[i] = np.argsort(d)[: args.k]

    base.astype(np.float32).tofile(os.path.join(args.outdir, "base.f32"))
    query.astype(np.float32).tofile(os.path.join(args.outdir, "query.f32"))
    gt.tofile(os.path.join(args.outdir, "gt.i32"))
    with open(os.path.join(args.outdir, "meta.txt"), "w", encoding="utf-8") as fh:
        fh.write(f"dim={args.dim}\nbase={args.n}\nqueries={args.nq}\ngt_k={args.k}\n"
                 f"clusters={args.clusters}\ngenerator=synthetic\n")
    print("synthetic dataset ->", args.outdir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
