# 项目①（向量检索服务）全过程记录

> 这份文件回答"我们到底做了什么、为什么这么做、数字从哪来"。
> 代码与数据的存放位置、每个结论的证据出处，都记在这里，方便你写作业和答辩。

- 项目：课程项目① —— 真实应用负载（SIFT1M 上的 HNSW 向量检索服务）的全栈性能优化
- 执行机器：**阿里云 ECS `114.215.202.9`**（`/root/proj1`），本地副本 `E:\System_Optimization\proj1`
- 执行时间：2026-11-22 13:35 – 14:45（含索引构建）
- 结论：**18,672 → 39,319 QPS（2.11×）**，`Recall@10` 恒为 0.9516，p99 = 430 µs

---

## 0. 先厘清三台机器的关系（容易搞混）

| 机器 | 上面是什么 | 和本项目①的关系 |
|---|---|---|
| `114.215.202.9` | **项目① 本体**（16 vCPU/8 物理核、30 GiB、Ubuntu 22.04） | 就是它 |
| `8.136.145.49` | 另一个项目：LLVM BOLT 的 L1i 冲突 padding pass | 无关 |
| `112.124.105.225` | 另一个项目：选题 3 索引推荐（PG16 + HypoPG + TPC-H） | 无关 |

## 1. 目标与约束

- 业务场景：RAG / 推荐 / 以图搜图的在线向量召回。
- 业务指标（写进 SLO）：`Recall@10 ≥ 0.95` 且 `p99 ≤ 500 µs` 前提下的最大 QPS；单次查询成本。
- 数据集：**SIFT1M**（1,000,000 × 128 维 float32，L2），10,000 条查询，官方 top-100 ground truth。
- 课程要求：真实负载、可复现、**至少两个软硬件不同层次**的优化、完整"测量→分析→优化→验证"闭环。
- 不使用矩阵乘法（教学样例）与 Redis（课上案例）。

## 2. 时间线

| 时间 | 动作 | 结果 |
|---|---|---|
| 13:35 | SSH 登录，确认 16 vCPU = **8 物理核 × HT**、30 GiB、单 NUMA | 记入 `results/env.txt` |
| 13:36 | 装工具链；测 PMU | `perf stat -e cycles` → **`<not supported>`**（云 VM 不给 PMU），决定用软件事件 + 火焰图 + llvm-mca 替代 |
| 13:38 | 写代码：`server.cpp` / `client.cpp` / `probe.cpp` / `l2kernel.c` | 见 `src/` |
| 13:41 | 下载 SIFT1M | 单连接仅 0.35 MB/s，改用 `aria2c -x16` ≈ 20 MB/s |
| 13:42–13:53 | **踩坑 1**：第一次用 `timeout 25` 打断 aria2，留下预分配（零填充）的 501 MB 文件 → `neighbors` 全 0、recall = 0.0000；用 `--file-allocation=none` 重下，校验 `neighbors[0][:8]` 是分散 id、距离量级 ~232，重建索引 | 索引 630 MB，构建约 90 s（450 CPU·s / 8 线程） |
| 13:54 | 首次有效基线 | 20,389 QPS、recall 0.9505 |
| 13:54–14:12 | 主实验矩阵（ef / threads / batch / THP / TCP / cpuset） | 58 个测量点 |
| 14:10 | **踩坑 2**：`SO_BUSY_POLL` 常量写成 `47`（实际 46），误设成 `SO_MAX_PACING_RATE=50`（B/s），服务被限速挂死 | 改用 `#ifdef SO_BUSY_POLL` 宏；重编译 |
| 14:25 | **踩坑 3**：`bench.sh` 里 `pkill -f vecserver` 会匹配到自己的命令行（`--bin ...vecserver_O3`），把压测脚本自己杀掉 | 改为 `pkill -x vecserver` |
| 14:30 | **踩坑 4**：`touch` 产生空 `raw.csv`，脚本因 `-f` 判断跳过表头 → pandas 报 `KeyError: label` | 补表头 |
| 14:36–14:40 | 补测绑核（SMT 感知 / 4 核）、编译档位、端到端终态 | 终态 39,319 QPS |
| 14:39–14:40 | `perf record` 火焰图 + `perf stat` + `llvm-mca` | 74.7% 时间在 AVX-512 距离核 |
| 14:40 | 绘图、生成汇总、写报告 | 4 张图 + `report.md` |

## 3. 系统设计与协议

```
client (闭环, N 线程)  ──TCP──▶  server (SO_REUSEPORT, M worker)
                                  └─ hnswlib HNSW 索引（630 MB，常驻）
请求: [u32 nq][u32 k] + nq×128 float32
应答: nq×k u32（label id）
```

- 服务端：`SO_REUSEPORT` 每个 worker 一个 listen fd（内核按连接散列），`accept` 后 `TCP_NODELAY`；
  可选 `SO_BUSY_POLL`；`searchKnn` 并发安全。
- 客户端：闭环、逐请求 `CLOCK_MONOTONIC` 打点，输出 `qps,p50,p90,p95,p99,max,requests,recall,errors`，
  recall 由 10,000 条查询与官方 gt 求交集。
- `probe.cpp`：直接加载索引 + 暴力检索对比，用于**排除"索引坏了"这类假象**（本次就是靠它定位到数据集损坏）。

## 4. 实验矩阵与结果（82 个测量点，`results/raw.csv`）

### 基线
`-O2`、8 worker、ef=64、THP=madvise、客户端 8 线程、不绑核 → **18,672 QPS**，p50 274 µs，p99 351 µs，recall 0.9516。
单线程 3,931 QPS（254 µs/查询）。

### 应用层
| 实验 | 结果 |
|---|---|
| worker 数 1/2/4/8/12/16 | 3,931 / 7,854 / 15,131 / 24,774 / 28,959 / 28,745 → 4 线程近似线性，12 线程到平台期 |
| efSearch 16/32/**64**/128/256 | QPS 44,776 / 30,296 / 21,766 / 12,596 / 7,171；recall 0.79 / 0.89 / **0.95** / 0.98 / 0.98 |
| `-O2` → `-O3` → `-O3 -march=native` | 18,672 → 21,555（1.15×）→ **23,373（1.25×，p50 −20%）** |
| 批处理 nq=1/4/16 | QPS 18,434 / 19,992 / 20,392（噪声内）；单请求 p50 277 → 999 → 3,888 µs → **不采纳** |

### OS 层
| 实验 | 结果 |
|---|---|
| THP always / madvise / never | 19,567 / 18,586 / **15,218** → 关 THP 损失 ~18% |
| 绑核：不绑 / 4 物理核(0-7) / 8 物理核(0,2,…,14) | 18,672 / 16,514（p99 **479**）/ 18,659（p99 346）→ 超线程兄弟共享代价：−12% 吞吐、+38% 尾延迟 |
| TCP_NODELAY 关 / SO_BUSY_POLL=50 / cpuset 隔离 | 18,586 / 18,714 / 18,811 → **均无收益**（loopback 无 Nagle 问题；virtio 不支持忙轮询；隔离只降低方差） |

### 端到端
| 配置 | QPS | p50 | p99 | recall |
|---|---|---|---|---|
| 基线 | 18,672 | 274 | 351 | 0.9516 |
| native + 12 worker + THP=always | 34,506 | 240 | 406 | 0.9516 |
| **native + 16 worker + THP=always** | **39,319** | 315 | **430** | 0.9516 |

分解：并发 1.54× × 编译/SIMD 1.37× × THP 1.05× ≈ 2.2×，与实测 2.11× 吻合。

### 微体系结构层证据（PMU 不可用下的替代）
- 火焰图（999 Hz，`-e cpu-clock`）：`L2SqrSIMD16ExtAVX512` **74.7%**、`searchBaseLayerST` 16.0%、
  系统调用路径 4.5% → 这就是"批处理无收益"的先验依据。
- `perf stat`：3.82 CPUs utilized、5.2 K context-switch/s、93 CPU 迁移。
- `llvm-mca`：`-O2`/`-O3` 的标量内核 ≈11 cycles/元素，`-march=native` 每轮处理 16 个 float、
  单元素周期数下降一个数量级；端到端只有 1.25× 是 Amdahl（GCC 在 -O2 已用 SSE2 自动向量化）。

## 5. 结论（可直接写进报告/答辩）

1. 负载是纯 CPU-bound、距离计算主导；**并发度 + SIMD** 是主战场，系统调用不是。
2. 达到 **2.11×** 吞吐（同 recall、p99 仍在 SLO 内），应用层贡献主要增益，OS 层（THP、绑核）贡献稳定性与尾延迟。
3. **负结果同样有价值**：批处理、TCP_NODELAY、SO_BUSY_POLL 被数据排除，说明优化是数据驱动。
4. 云 VM 无 PMU 是硬约束，用火焰图 + 静态建模替代，并在报告里明示——这本身是"落地约束"论证。
5. 噪声：同一配置重复之间波动 15%–30%，故一律 3 次重复取中位数并报范围；<5% 的差异不作结论。

## 6. 文件清单

| 位置 | 内容 |
|---|---|
| `src/server.cpp` | 检索服务（TCP + hnswlib，多 worker，可选 NODELAY/BUSYPOLL） |
| `src/client.cpp` | 闭环压测客户端（QPS + 分位延迟 + recall@k） |
| `src/probe.cpp` | 索引正确性探针（与暴力检索比对） |
| `src/l2kernel.c` | 独立 L2 距离核（供 llvm-mca） |
| `scripts/prepare_data.py` / `make_synthetic.py` | hdf5 → raw 二进制 / 合成兜底数据 |
| `scripts/build.sh` | 三个编译档位的服务端 + 客户端 |
| `scripts/bench.sh` / `run_all.sh` | 单点压测 / 实验矩阵 |
| `scripts/perf_profile.sh` / `mca.sh` | 软件事件采样 / 静态流水线分析 |
| `scripts/plot.py` / `summarize.py` / `sysinfo.sh` | 绘图 / 汇总表 / 环境记录 |
| `results/raw.csv` | 82 个原始测量点 |
| `results/summary.md` | 中位数汇总表 |
| `results/env.txt` | 环境快照（CPU/内核/THP/sysctl/工具链版本） |
| `results/figures/*.png` | 4 张图（ef 权衡、线程扩展、收益汇总、延迟对比） |
| `results/perf/` | perf 统计、符号热点、采样原始脚本（`perf-script.txt` 23 MB） |
| `results/mca/` | 三档汇编 + llvm-mca 报告 |
| `report.md` | 研究报告正文 |
| `README.md` | 复现步骤与实验矩阵 |

## 7. 只存在于服务器、不在本地的体积项（需要的话可以拉下来）

| 路径（服务器 `/root/proj1/`） | 大小 | 能否重建 |
|---|---|---|
| `data/sift.hdf5` | 501 MB | 可重下（aria2，约 30 s） |
| `data/base.f32` `query.f32` `gt.i32` | 512 + 5 + 4 MB | `scripts/prepare_data.py` 可再生 |
| `data/index.bin` | 630 MB | 首次启动自动重建（约 90 s） |
| `build/vecserver*` `vecclient` `probe` | ~0.4 MB | `scripts/build.sh` |
| `hnswlib/` | ~10 MB | `codeload.github.com/nmslib/hnswlib` 拉取 |

本地已包含**代码、脚本、全部结果、报告、图表**共 40 个文件 / 28.3 MB，不含上述可再生的体积项。

## 8. 待办（如果继续做）

1. **多机压测**：再开一台同可用区实例当客户端，量化"同机"对可达吞吐的压制。
2. **PMU 补采**：租 1 天弹性裸金属，补 CPI/MPKI，让微体系层证据齐全。
3. 报告排版：Markdown → Word/PDF（图表、目录、页码）。
4. 安全加固：禁用密码登录、限制安全组 22 端口来源。
