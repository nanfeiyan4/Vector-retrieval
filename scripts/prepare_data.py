#!/usr/bin/env python3
"""Convert ann-benchmarks SIFT hdf5 into raw little-endian binary files.

Outputs (all in --outdir):
  base.f32    N x D float32, row-major
  query.f32   Q x D float32
  gt.i32      Q x 100 int32 (exact L2 neighbours, ground truth)
"""
import argparse
import os
import sys

import h5py
import numpy as np


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hdf5", default="/root/proj1/data/sift.hdf5")
    ap.add_argument("--outdir", default="/root/proj1/data")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    with h5py.File(args.hdf5, "r") as f:
        print("keys:", list(f.keys()))
        base = np.asarray(f["train"], dtype=np.float32)
        query = np.asarray(f["test"], dtype=np.float32)
        gt = np.asarray(f["neighbors"], dtype=np.int32)
    print(f"base={base.shape} query={query.shape} gt={gt.shape}")

    for name, arr in (("base.f32", base), ("query.f32", query), ("gt.i32", gt)):
        path = os.path.join(args.outdir, name)
        arr.tofile(path)
        print(f"wrote {path} ({os.path.getsize(path)/1e6:.1f} MB)")

    meta = os.path.join(args.outdir, "meta.txt")
    with open(meta, "w", encoding="utf-8") as fh:
        fh.write(f"dim={base.shape[1]}\nbase={base.shape[0]}\nqueries={query.shape[0]}\n"
                 f"gt_k={gt.shape[1]}\nsource={args.hdf5}\n")
    print("wrote", meta)
    return 0


if __name__ == "__main__":
    sys.exit(main())
