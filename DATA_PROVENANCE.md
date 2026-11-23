# 数据来源与校验（DATA PROVENANCE）

这份文档的作用只有一个：**让任何人能证明"我跑实验用的数据"和"你下载到的数据"是同一份字节**，
而不是靠一句"我用的是 SIFT1M"。

所有数值均可复算，命令在最后一节。

---

## 1. 原始数据集

| 项 | 值 |
|---|---|
| 名称 | SIFT1M（ann-benchmarks 发行版，L2 距离） |
| URL | `http://ann-benchmarks.com/sift-128-euclidean.hdf5` |
| 大小 | **525,128,288 bytes**（500.8 MiB） |
| SHA-256 | `dd6f0a6ed6b7ebb8934680f861a33ed01ff33991eaee4fd60914d854a0ca5984` |
| HDF5 magic | `89 48 44 46 0d 0a 1a 0a`（`\x89HDF\r\n\x1a\n`） |
| HTTP ETag | `"2bf1ef4c0c3e17031bd64980774eea09-63"` |
| Last-Modified | `Mon, 09 Dec 2024 03:38:44 GMT` |
| 容器内结构 | `train (1000000×128 f32)`、`test (10000×128 f32)`、`neighbors (10000×100 i32)`、`distances (10000×100 f32)` |

**关于 ETag 的说明（避免误判）**：末尾的 `-63` 表明该对象在源站由 63 个分片上传，
按 S3 规则此时 ETag **不等于**整文件 MD5，只是"分片 MD5 串接后的 MD5"。所以校验请用上表的
**SHA-256**，不要用 ETag 去和 `md5sum` 比对。

## 2. 派生产物（实验真正读取的文件）

`scripts/prepare_data.py` 把 hdf5 摊平成裸二进制，C++ 服务端直接 `read`，不依赖任何库：

| 文件 | 大小 (bytes) | SHA-256 | 含义 |
|---|---:|---|---|
| `data/base.f32` | 512,000,000 | `ac8e11ed111b09e882bcf0ef1a77ebdd36c89f495bce8fd596603f69c35148e6` | 1,000,000 × 128 float32，行主序（= `train`） |
| `data/query.f32` | 5,120,000 | `bf4c4c9db385017e63e7b0a9ccd8e3aab3744a02e053c135e000fa0b1dea2d6f` | 10,000 × 128 float32（= `test`） |
| `data/gt.i32` | 4,000,000 | `4d880e63ec1ad02ea3a0827089f92bf2560bc59a74900c5feeb62903265bb870` | 10,000 × 100 int32，精确 L2 近邻（= `neighbors`） |
| `data/meta.txt` | 72 | — | 维度/行数/来源记录 |

语义约定（`prepare_data.py` 就是照此实现的，别自己换顺序）：

- base 的第 `i` 行就是索引里的 `label = i`，`Recall@10` 的比对依赖这一点；
- `gt.i32` 的列按距离升序，前 10 列即 `Recall@10` 的参照；
- 距离为**平方 L2**（hnswlib 的 `L2Space` 同样用平方距离），不影响排序。

## 3. 一个刻意的例外：`index.bin` 不做校验

| 项 | 值 |
|---|---|
| 路径 | `data/index.bin`（约 630 MB） |
| 构建参数 | `M = 16`，`efConstruction = 200`，8 线程并行插入 |
| 重建耗时 | 约 90 s（16 vCPU） |

**为什么不给它的哈希**：hnswlib 的插入是**多线程并行**的，线程交错不同会让同一份 base 生成的图
在字节层面不同（节点编号顺序、邻居表的具体取舍）。两次构建的索引**并非逐字节可复现**，但对
检索质量与吞吐的统计特性等价——我们实测过两次独立构建，`Recall@10` 都是 0.9516、QPS 差异在
测量噪声内。

所以：**可复现性锚定在 `base.f32` + 构建参数 + 代码**，不锚定索引字节。谁要复跑，删掉
`index.bin` 让服务首次启动自动重建即可。

## 4. 实验参数（与数据强耦合，必须一起记录）

| 参数 | 值 |
|---|---|
| 度量 | 平方 L2 |
| `k` | 10 |
| 业务工作点 | `efSearch = 64` ⇒ `Recall@10 = 0.9516` |
| 每次测量查询数 | 200,000（约 10 s 窗口） |
| 预热 | 100 个请求 |
| 重复次数 | 3（取中位数，同时报范围） |
| 服务端 | `src/server.cpp`，SO_REUSEPORT，worker 数 1–16 |
| 客户端 | `src/client.cpp`，闭环，逐请求 `CLOCK_MONOTONIC` 打点 |

## 5. 机器与工具链（数据之外的可复现性）

摘自 `results/env.txt`（测量当时由 `scripts/sysinfo.sh` 落地）：

| 项 | 值 |
|---|---|
| 平台 | 阿里云 ECS，KVM，`cn-hangzhou` |
| CPU | Intel Xeon Platinum（Skylake 级），16 vCPU = 8 物理核 × 2 超线程，单 NUMA，L3 33 MiB |
| 内存 / 磁盘 | 30 GiB / 200 GiB ext4（ESSD） |
| OS | Ubuntu 22.04.5，kernel 5.15.0-198 |
| 编译器 | g++ 11.4.0 |
| perf | 5.15.216（**PMU 不可用**：`cycles/instructions` 均 `<not supported>`） |

## 6. 自检断言（3 条，10 秒内可跑完）

派生数据正确时，这三条必须成立：

```text
gt[0][:8]        = [932085, 934876, 561813, 708177, 706771, 695756, 435345, 701258]
distances[0][:5] ≈ [232.87, 234.71, 243.99, 255.46, 256.31]   (平方 L2)
shape            = base (1000000,128) / test (10000,128) / neighbors (10000,100)
```

> 这三条是用**实验当时那台机器上生成的数据**核对的；本次在本机重新派生后又核了一遍，
> 结果一致——所以本地这份数据与实验所用数据同源同内容。

## 7. 如何从零复核

```bash
pip3 install h5py numpy

# 取数：单连接只有 ~0.3 MB/s（525 MB 要 28 min），24 连接约 36 s
python3 scripts/fetch_parallel.py \
  --url http://ann-benchmarks.com/sift-128-euclidean.hdf5 \
  --out data/sift.hdf5 \
  --sha256 dd6f0a6ed6b7ebb8934680f861a33ed01ff33991eaee4fd60914d854a0ca5984

# 派生 + 校验
python3 scripts/prepare_data.py --hdf5 data/sift.hdf5 --outdir data
sha256sum data/base.f32 data/query.f32 data/gt.i32
```

若 `fetch_parallel.py` 打印的 sha256 与第 1 节一致，`sha256sum` 的三个值与第 2 节一致，
且第 6 节的断言全部通过，即可确认复现的是同一份数据。

---

记录时间：2026-11-23　数据获取方式：24 路并行 range 下载（`scripts/fetch_parallel.py`）
