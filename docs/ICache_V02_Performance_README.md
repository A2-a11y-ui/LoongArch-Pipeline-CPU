# I-Cache V0.2 性能对比实验：Vivado 2019.1

## 目的及已完成基线

- V0.1 (`icache.v`) 已经通过用户实际 Vivado 2019.1 独立测试：157 项检查、0 错误。
- **不要修改、覆盖或者移除原有的 `icache.v`、`tb_icache.v` 和 `imem.v`。** V0.2 是单独的性能模型，避免影响稳定基线。
- 原 `imem.v` 为理想组合 ROM，无法直接用于可信的「有 Cache vs 无 Cache」延迟对比。

## 新文件及职责

| 新文件 | 作用 | 加入 Vivado |
|---|---|---|
| `rtl/memory_cache/imem_latency.v` | **同一参数** LATENCY=3 周期的后备存储器、单事务握手、记录实际读字次数 | Design Sources |
| `rtl/memory_cache/if_direct_latency.v` | 无 Cache 的直接取指基线控制器，一条取指读取一个后备字 | Design Sources |
| `rtl/memory_cache/icache_latency.v` | 16 行×4 字的直接映射 Cache，增加 mem_ready 握手，Miss 回填 4 字 | Design Sources |
| `tb/tb_icache_performance.v` | 相同的存储器模型、相同访问序列、自动核对取回值、统计性能 | Simulation Sources |

**本测试是 fetch-only benchmark（取指子系统对比），不代表真实单周期 CPU 的整体 CPI，也不包含分支预测、Flush、流水线时钟闭合。** 两条路径使用完全相同的 1 KiB ROM 数据和后备访问 LATENCY=3；Cache 按 4 字整行回填，基线仅取当前 1 字，这是有意测量的真实读流量差异。

## Vivado 操作

1. GitHub Desktop 确认当前分支 `feature/icache`，先 Commit/Push V0.1 的修改。
2. 解压本包，按相对目录复制到 `D:\CPU_Project\LoongArch-Pipeline-CPU`；**不要覆盖旧文件**。
3. Vivado 2019.1 → Add Sources → Add or Create Design Sources，添加三个新的 RTL 文件；**不要把 `tb_icache_performance.v` 加到 Design Sources**。
4. Add Sources → Add or Create Simulation Sources，添加 `tb/tb_icache_performance.v`。
5. 在 Sources 中右键 `tb_icache_performance` → Set as Top。
6. Run Simulation → Run Behavioral Simulation。模拟总时长可能超过默认的 1000 ns；本 Testbench 自带 `$finish`，如果控制台没有最终统计，可在 Tcl Console 输入 `run all` 继续直到 `$finish`。
7. 保存 Tcl Console 的三种模式性能统计、最后的 `Total errors=0` 和波形截图，用于课程报告。

## 三种测试模式（每次独立复位，双方 ROM 数据相同）

| Pattern | 访问序列 | 请求数 | 理论 Hit | 理论 Miss | 理论回填字数 | 结论预期 |
|---|---|---:|---:|---:|---:|---|
| 0 顺序访问 | 32 字（8 行），重复 3 轮 | 96 | 88 | 8 | 32 | Cache 取指更快 |
| 1 热点循环 | 4 字（1 行），重复 16 轮 | 64 | 63 | 1 | 4 | Cache 取指更快 |
| 2 冲突访问 | 0 和 0x100 交替（相同 Index） | 32 | 0 | 32 | 128 | Cache **可能更慢** |

其他测试：越界与未对齐地址不产生后备访问；两种路径读到的指令字都必须与相同的 ROM 数据一致。

## 指标解释与报告写法

- **Hit rate** = hit_count / (hit_count + miss_count)。注：来自完整请求序列，而不是只看结束前最后一次复位的计数。
- **Fetch cycles per instruction** = 完成所有请求使用的总取指时钟周期 / 指令请求总数；本工程按成功取指握手计时。
- **Fetch-only speedup** = baseline_cycles / cached_cycles。该比值在相同仿真时钟假设下比较，不等同于整体 CPU 加速比。
- **Backing-memory traffic**：无 Cache 按请求数逐字读取；Cache 按每次 Miss 四字回填。冲突访问可能产生高于无 Cache 的流量，必须如实解释。
- 当前 RTL 是独立性能比较模型，尚未定论 FPGA LUT/FF/BRAM、Fmax 或真实流水线 CPI。等队员 A 完成 IF Stall/Flush 协议后再接入流水线，并综合同一目标 EGO1 Artix-7 器件报告资源/时序。

## 测试结果

这份代码由我生成，**未在用户的 Vivado 2019.1 上实测**。不要在实际仿真完成前把预期数值写成实验已测数据。如果出现编译或功能 FAIL，请发第一条 ERROR/FAIL 及相应波形。

## 提交建议

仅在完成仿真和审查后提交这四份文件（以及本文档）到 `feature/icache`，建议 Commit：`Benchmark direct-mapped I-Cache with fixed-latency memory`。
