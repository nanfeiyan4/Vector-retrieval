#!/usr/bin/env python3
"""Aggregate results/raw.csv into a markdown table (median of repeated runs)."""
import os
import sys

import pandas as pd

ROOT = os.environ.get("ROOT", "/root/proj1")
CSV = os.path.join(ROOT, "results", "raw.csv")

ORDER = ["baseline", "smoke1m", "build-O3", "build-native",
         "ef16", "ef32", "ef64", "ef128", "ef256",
         "sthreads1", "sthreads2", "sthreads4", "sthreads8", "sthreads12", "sthreads16",
         "batch1", "batch4", "batch16",
         "thp-always", "thp-never", "thp-madvise", "nodelay-off", "busypoll-50", "cpuset-isolated"]


def main() -> int:
    df = pd.read_csv(CSV)
    g = (df.groupby("label")
           .agg(qps=("qps", "median"),
                qps_min=("qps", "min"),
                qps_max=("qps", "max"),
                p50=("p50_us", "median"),
                p99=("p99_us", "median"),
                recall=("recall", "median"),
                reps=("qps", "size"))
           .reset_index())
    base = g.loc[g["label"] == "baseline", "qps"]
    base_qps = float(base.iloc[0]) if len(base) else float("nan")

    labels = [l for l in ORDER if l in set(g["label"])]
    labels += [l for l in g["label"] if l not in labels]
    g = g.set_index("label").loc[labels].reset_index()

    print("| 配置 | QPS(中位数) | QPS 范围 | 相对基线 | p50 (µs) | p99 (µs) | Recall@10 | 重复次数 |")
    print("|---|---|---|---|---|---|---|---|")
    for _, r in g.iterrows():
        rel = f"{r['qps']/base_qps:.2f}x" if base_qps == base_qps else "-"
        print(f"| {r['label']} | {r['qps']:,.0f} | {r['qps_min']:,.0f}–{r['qps_max']:,.0f} | "
              f"{rel} | {r['p50']:.1f} | {r['p99']:.1f} | {r['recall']:.4f} | {int(r['reps'])} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
