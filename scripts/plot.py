#!/usr/bin/env python3
"""Turn results/raw.csv into the figures used by the report."""
import os
import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

ROOT = os.environ.get("ROOT", "/root/proj1")
CSV = os.path.join(ROOT, "results", "raw.csv")
FIG = os.path.join(ROOT, "results", "figures")


def agg(df, label):
    g = df[df["label"] == label]
    if g.empty:
        return None
    return {
        "qps": g["qps"].median(),
        "p50": g["p50_us"].median(),
        "p99": g["p99_us"].median(),
        "recall": g["recall"].median(),
    }


def main() -> int:
    os.makedirs(FIG, exist_ok=True)
    df = pd.read_csv(CSV)
    print(df.groupby("label")[["qps", "p50_us", "p99_us", "recall"]].median().round(3))

    # fig 1: QPS vs efSearch (recall annotated)
    rows = []
    for e in sorted(df.loc[df["label"].str.startswith("ef"), "ef"].unique()):
        r = agg(df, f"ef{e}")
        if r:
            rows.append((e, r["qps"], r["p99"], r["recall"]))
    if rows:
        fig, ax = plt.subplots(figsize=(6.4, 4.0))
        ax.plot([r[0] for r in rows], [r[1] for r in rows], "o-", label="QPS")
        ax.set_xlabel("efSearch")
        ax.set_ylabel("QPS")
        ax.set_xscale("log", base=2)
        ax.grid(alpha=0.3)
        ax2 = ax.twinx()
        ax2.plot([r[0] for r in rows], [r[3] for r in rows], "s--", color="tab:red", label="recall@10")
        ax2.set_ylabel("recall@10")
        ax.set_title("Throughput vs recall trade-off")
        fig.tight_layout()
        fig.savefig(os.path.join(FIG, "fig1_ef_qps_recall.png"), dpi=150)
        plt.close(fig)

    # fig 2: QPS vs server threads
    rows = []
    for t in sorted(df.loc[df["label"].str.startswith("sthreads"), "sthreads"].unique()):
        r = agg(df, f"sthreads{t}")
        if r:
            rows.append((t, r["qps"], r["p99"]))
    if rows:
        fig, ax = plt.subplots(figsize=(6.4, 4.0))
        ax.plot([r[0] for r in rows], [r[1] for r in rows], "o-", label="QPS")
        ax.set_xlabel("server worker threads")
        ax.set_ylabel("QPS")
        ax.set_title("Scaling with worker threads (client 16 threads)")
        ax.grid(alpha=0.3)
        ax2 = ax.twinx()
        ax2.plot([r[0] for r in rows], [r[2] for r in rows], "s--", color="tab:red")
        ax2.set_ylabel("p99 (us)")
        fig.tight_layout()
        fig.savefig(os.path.join(FIG, "fig2_threads.png"), dpi=150)
        plt.close(fig)

    # fig 3: optimisation summary bar chart
    order = ["baseline", "build-O3", "build-native", "batch4", "batch16",
             "thp-always", "thp-never", "nodelay-off", "busypoll-50", "cpuset-isolated"]
    labels, qps, p99 = [], [], []
    base = agg(df, "baseline")
    for lab in order:
        r = agg(df, lab)
        if r:
            labels.append(lab)
            qps.append(r["qps"])
            p99.append(r["p99"])
    if labels:
        fig, ax = plt.subplots(figsize=(9, 4.2))
        xs = range(len(labels))
        ax.bar(xs, qps, color="tab:blue", alpha=0.8)
        ax.set_xticks(list(xs))
        ax.set_xticklabels(labels, rotation=30, ha="right")
        ax.set_ylabel("QPS")
        if base:
            ax.axhline(base["qps"], color="gray", ls="--", lw=1)
        for i, q in enumerate(qps):
            ax.text(i, q, f"{q/base['qps']:.2f}x" if base else f"{q:.0f}",
                    ha="center", va="bottom", fontsize=7)
        ax.set_title("Optimisation summary (relative to baseline)")
        fig.tight_layout()
        fig.savefig(os.path.join(FIG, "fig3_summary.png"), dpi=150)
        plt.close(fig)

    # fig 4: latency comparison
    if labels:
        fig, ax = plt.subplots(figsize=(9, 3.6))
        w = 0.38
        p50 = [agg(df, lab)["p50"] for lab in labels]
        ax.bar([x - w / 2 for x in xs], p50, w, label="p50")
        ax.bar([x + w / 2 for x in xs], p99, w, label="p99")
        ax.set_xticks(list(xs))
        ax.set_xticklabels(labels, rotation=30, ha="right")
        ax.set_ylabel("latency (us)")
        ax.legend()
        ax.set_yscale("log")
        ax.set_title("Latency by configuration")
        fig.tight_layout()
        fig.savefig(os.path.join(FIG, "fig4_latency.png"), dpi=150)
        plt.close(fig)

    print("figures ->", FIG)
    return 0


if __name__ == "__main__":
    sys.exit(main())
