# 项目①：向量检索服务（HNSW）的全栈性能优化

一门「软件系统优化」课程项目的完整实验工程：在真实应用负载（SIFT1M 向量检索服务）上，
按「应用层 → 操作系统层 → 微体系结构层」自顶向下的方法定位瓶颈、实施优化并验证收益。

## 1. 业务场景与指标

向量检索是 RAG、推荐、以图搜图等业务的在线召回组件，业务方对它的要求是**在给定的召回精度下**
尽可能高的吞吐和可控的尾延迟：

| 层次 | 指标 | 说明 |
|---|---|---|
| 业务 | `Recall@10 ≥ 0.95` 约束下的最大 QPS | 精度不达标吞吐再高也没用 |
| 业务 | 单次查询成本（核·秒/查询） | 云上直接折算成钱 |
| 服务 | p50 / p95 / p99 延迟 | SLO 通常写在 p99 上 |
| 系统 | CPU 时间构成、上下文切换、IPC | 定位瓶颈用 |

本项目用 **SINT1M（1,000,000 × 128 维，L2 距离）** 作为数据集，10,000 条查询，
官方 ground truth 前 100 近邻；`Recall@10` 与吞吐同时报告。

## 2. 目录结构

```
proj1/
├── src/
│   ├── server.cpp      # 向量检索服务：TCP + hnswlib，SO_REUSEPORT 多 worker
│   ├── client.cpp      # 闭环压测客户端：QPS + 分位延迟 + recall@k
│   ├── probe.cpp       # 索引正确性探针（与暴力检索比对）
│   └── l2kernel.c      # 独立的 L2 距离内核，用于 llvm-mca 静态分析
├── scripts/
│   ├── prepare_data.py     # SIFT hdf5 -> raw f32/i32
│   ├── make_synthetic.py   # 合成数据集（离线兜底）
│   ├── build.sh            # 三个版本的服务器（-O2 / -O3 / -O3 -march=native）
│   ├── bench.sh            # 单个实验点：起服务、压测 3 次、写 CSV
│   ├── run_all.sh          # 实验矩阵驱动
│   ├── sysinfo.sh          # 记录测量环境
│   ├── perf_profile.sh     # 软件事件 perf + 调用栈采样
│   └── plot.py             # 生成报告图表
└── results/                # raw.csv / figures / perf / logs
```

## 3. 复现步骤

```bash
# 0) 依赖
apt-get install -y build-essential linux-tools-5.15.0-198-generic \
                   numactl hyperfine llvm clang python3-pip aria2
pip3 install h5py numpy matplotlib pandas

# 1) 取 hnswlib（header-only）
curl -sSL https://codeload.github.com/nmslib/hnswlib/tar.gz/refs/heads/master \
  | tar xz && mv hnswlib-* hnswlib

# 2) 取数据集（多连接下载，单连接约 0.35 MB/s，aria2 约 20 MB/s）
aria2c -x16 -s16 -k1M -o data/sift.hdf5 \
  http://ann-benchmarks.com/sift-128-euclidean.hdf5
python3 scripts/prepare_data.py          # -> data/base.f32 query.f32 gt.i32

# 3) 编译
bash scripts/build.sh

# 4) 第一次启动会自动建索引（1M 点，8 线程，约 90 s），随后跑完整矩阵
bash scripts/run_all.sh all              # 约 15 min
python3 scripts/plot.py                  # -> results/figures/*.png
bash scripts/sysinfo.sh                  # -> results/env.txt
```

单独跑一个实验点：

```bash
bash scripts/bench.sh --label mytest --ef 64 --sthreads 8 --cthreads 8 \
     --nq 1 --nqtotal 200000 --reps 3 --thp always --server-cpus 0-11 --client-cpus 12-15
```

## 4. 实验矩阵

| 阶段 | 配置 | 层次 |
|---|---|---|
| baseline | `-O2`，8 workers，ef=64，THP=madvise | — |
| ef sweep | efSearch = 16/32/64/128/256 | 应用（精度-吞吐权衡） |
| threads | 1/2/4/8/12/16 workers | 应用（并发度） |
| batch | 每请求 1/4/16 条查询 | 应用（摊薄系统调用） |
| build flags | `-O2` → `-O3` → `-O3 -march=native`（AVX2/AVX-512 距离核） | 应用/编译 |
| THP | always / madvise / never | OS（内存页） |
| TCP | TCP_NODELAY 开/关、SO_BUSY_POLL | OS（网络栈） |
| cpuset | 无隔离 vs 服务端 0-11 / 客户端 12-15 | OS（调度/缓存干扰） |

## 5. 输出

`results/raw.csv` 每行一个测量点（`label,ef,sthreads,cthreads,nq_per_req,rep,qps,p50,p90,p95,p99,max,requests,recall,errors`），
取 3 次重复的中位数后画图；`results/perf/` 是软件事件与调用栈证据；
`results/mca/` 是 llvm-mca 对距离内核的静态流水线分析（本机无 PMU）。
