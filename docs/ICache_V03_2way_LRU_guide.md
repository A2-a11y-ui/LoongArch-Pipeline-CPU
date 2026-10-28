# LoongArch I-Cache V0.3：256B 2 路组相联 + LRU 对照实验

## 1. 本阶段任务

在 **不修改已通过 2816 项测试的 V0.2** 前提下，增加一个相同数据容量的两路组相联 I-Cache。使用完全相同的访问序列、相同的 `imem_latency` 以及 `LATENCY=3`，和无 Cache、直接映射 Cache 进行三路对比。

本阶段只是 **取指子系统** 仿真；不是整机 CPI、FPGA 硬件时序或资源报告。

## 2. 文件安排

| 新增文件 | Windows 项目位置 | Vivado 分类 |
|---|---|---|
| `icache_2way_latency.v` | `rtl/memory_cache/` | Design Sources |
| `tb_icache_2way_performance.v` | `tb/` | Simulation Sources |
| `ICache_V03_2way_LRU_guide.md` | `docs/` | 不需要加入 Vivado |

另外依赖现有 V0.2 的三个 RTL 文件：`icache_latency.v`（直接映射基线）、`imem_latency.v`（延迟后备存储器）、`if_direct_latency.v`（无 Cache 基线）。**保持它们原样，不要删除 `icache.v` V0.1。**

## 3. 结构及地址划分

| 参数 | 直接映射 V0.2 | 2 路组相联 V0.3 |
|---|---|---|
| 数据总容量 | 256 B | 256 B |
| Cache 行总数 | 16 | 16 |
| 每行字节 | 16 B | 16 B |
| 组数 | 16 | 8 |
| 每组路数 | 1 | 2 |
| 数据字数 | 64 | 64 |
| Index 位 | `addr[7:4]` | `addr[6:4]` |
| Tag 位 | `addr[31:8]` | `addr[31:7]` |
| 行内字索引 | `addr[3:2]` | `addr[3:2]` |
| 替换策略 | 覆盖映射行 | 优先空路；满组时 1-bit 真 LRU |

2 路组相联每组只有 2 路，所以每组一位 `lru_victim` 就足够实现准确的 LRU：访问某路后，将**另一条路**记为下次的替换候选；新填充某路后也同理。行必须填满 4 个 32 位字后才置 valid。

## 4. 访问协议

输入 `req_valid` 和 `req_addr`；输出 `ready/fetch_valid/stall/inst`。测试平台必须在 `stall=1` 的阶段保持地址与请求有效，直到 `ready=1`。后备接口采用 `mem_req` 单周期脉冲，以及 `mem_ready` 返回脉冲，取指 Miss 依次请求行内 4 个字。

目前仍只有单个未完成请求，尚不支持分支 `redirect` 时中止或取消正在回填的请求。五级流水线 IF 集成前必须专门加入 **redirect/flush、过期请求取消或丢弃、事务标记** 等机制，不能仅仅连接到 PC。

## 5. 测试计划与对照结果

测试平台 `tb_icache_2way_performance` 与 V0.2 采用相同三组轨迹，三条独立的延迟后备存储器实例，同一数据初始化。所有指令数据必须与 `0xA5000000 | (address >> 2)` 一致。

| 场景 | 请求 | 无 Cache | 直接映射期望 Hit/Miss | 2 路期望 Hit/Miss |
|---|---:|---|---|---|
| PATTERN 0，32 字工作集重复 3 轮 | 96 | 96 次后备读 | 88 / 8 | 88 / 8 |
| PATTERN 1，4 字热点循环 | 64 | 64 次后备读 | 63 / 1 | 63 / 1 |
| PATTERN 2，地址 0 与 0x100 交替 | 32 | 32 次后备读 | 0 / 32 | 30 / 2 |
| LRU 专测：0→0x80→0→0x100→0→0x80 | 6 | 不参与三个方案性能合计 | 不参与 | 2 / 4 |

以上两路 Hit/Miss 数字来自映射逻辑的**预期**，不是硬件仿真观察。真实周期、加速比和硬件资源数据必须根据你自己的 Vivado 输出填写。

### V0.2 已测参考数据（你提供的真实 XSim 输出）

| 场景 | 无 Cache 周期 | 直接映射周期 | 直接映射命中 | 直接映射缺失 |
|---|---:|---:|---:|---:|
| PATTERN 0 | 672 | 264 | 88 | 8 |
| PATTERN 1 | 448 | 85 | 63 | 1 |
| PATTERN 2 | 224 | 704 | 0 | 32 |

在相同接口时序下可用 `hit*1 + miss*22` 预测 V0.3 的取指周期（分别为 264、85、74），但这只是根据已测 V0.2 行为得出的**估算**，不得写成 V0.3 的实测值。

## 6. Vivado 2019.1 操作

1. GitHub Desktop 确认你位于 `feature/icache` 分支。未提交的改动先 Commit + Push。
2. `Add Sources` → `Add or Create Design Sources` → 加入 `icache_2way_latency.v`。
3. 确认 `icache_latency.v`、`imem_latency.v`、`if_direct_latency.v` 仍在 Design Sources。
4. `Add Sources` → `Add or Create Simulation Sources` → 加入 `tb_icache_2way_performance.v`。
5. 右键 `tb_icache_2way_performance` → `Set as Top` → `Run Behavioral Simulation`。
6. 如默认停留在 1000ns，打开 Tcl Console 输入 `run all`。
7. 截图包含 3 组 `PATTERN` 周期统计、`LRU TRACE`、`Total checks`、`Total errors` 与 `ALL TESTS PASSED` 的日志。不要因为控制台显示 1000ns 就认定仿真已结束。

### 预期验收

- 三条路径取指数据均与同一后备 ROM 内容匹配；所有非法地址不读后备存储器。
- PATTERN 0/1：2 路命中计数与直接映射相同。
- PATTERN 2：2 路命中 30 次、缺失 2 次；必须比直接映射快。
- LRU TRACE：命中 2 次、缺失 4 次；回填 16 字。
- 最终 `Total errors = 0`、`ALL TESTS PASSED`。

## 7. Git 提交建议

`Implement 2-way LRU I-Cache and compare with direct-mapped baseline`

只提交新增 RTL、Testbench、说明及实际测试数据；避免提交 `.sim`、`.runs`、`.cache` 等 Vivado 自动输出。

## 8. 注意的限制

- 两路命中需要并行比较两个 Tag，BRAM/LUT/比较器开销可能上升；只有综合和实现后才能评价资源及最大频率。
- 仿真模拟的是理想命中返回路径和固定延迟后备存储器，不等于板上的物理 ROM/DDR 延迟。
- 不支持请求取消、乱序、多未完成事务，不可直接套到带分支冲刷的五级流水线取指级。
