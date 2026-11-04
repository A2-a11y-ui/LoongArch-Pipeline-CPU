# V0.9 Stage3 — FPGA CPU Wrapper 独立整机回归计划

## 测试性质与边界

- DUT：`pipeline_cpu_fpga`（V0.9 的 FPGA-oriented CPU 包装模块），**不是** EGO1 实物板级 `ego1_top`；也不是 V0.8 原测试包装模块。
- 真实 I-Cache + Adapter + `imem_bram` + 多周期 `dmem_latency` + V0.8 Datapath；只新增仿真 Testbench，不改正式 RTL。
- 复用此前 V0.8 Stage3 通过的**相同 40 字机器码、独立黄金提交序列和预期 RAM**，以检查新的取指/BRAM 包装是否破坏功能。
- `v09_commit_scoreboard.v` 来自已合并的 PR #40，需列入 Simulation Sources。采用独立 WB、Store **事件**计分。

## DUT 参数

| 参数 | 本测试设置 |
|---|---|
| PC_BASE | `0x00001000` |
| PROGRAM_WORDS | 40 |
| IMEM_FILE | `tb/pipeline_cpu/programs/v09_stage3_hazard_mdu.mem`（Testbench 默认采用指定 Windows 仓库路径） |
| DMEM_READ_LATENCY | 8 |
| DMEM_WRITE_LATENCY | 11 |
| DMEM_WORDS | 256 |

## 固定预期（并非已实测）

| 指标 | 预期 |
|---|---|
| WB 提交 | 29/29；逐一检查 PC、rd、data |
| Store 提交 | 3/3；逐一检查 PC、地址、数据 |
| Branch resolve | 4 |
| Redirect | 2，目标 0x104C / 0x1070 |
| MDU Start/Result | 14/14 |
| DMEM Request/Response | 6/6，无重叠、无无源响应 |
| MDU Busy / MEM Stall / IF Hold | 均实际出现（周期数不强制等于 V0.8） |
| I-Cache | 至少一次 Hit、Miss 和 backing ROM transaction |
| FPGA 完成 | `program_done=1`，且 `fault_sticky=0` |
| 最终 RAM | word1=18、word2=0、word3=55、word4=0、word5=117 |
| 错误路径寄存器 | r15=0、r20=0 |
| 超时 | 20000 个时钟周期硬超时，任何错误以 `$fatal` 结束 |
| Errors | `OTHER_ERRORS=0`、`SB_ERRORS=0`、ALL TESTS PASSED |

所有预测值均基于 Stage3 独立参考结果，**不能因首次仿真失败而擅自改低预期**。如果出现差异，先保留第一条 FAIL 和关键波形，再检查程序加载、RTL 和参考模型。

## 目前状态

## 实测结果

验证工具：Vivado 2019.1

仿真顶层：tb_v09_stage3_fpga_cpu

测试对象：pipeline_cpu_fpga

- WB：29/29
- STORE：3/3
- BR：4
- REDIRECT：2
- MDU：14/14
- DMEM：6/6
- CACHE_HIT：28
- CACHE_MISS：10
- IF_HOLD：405
- PROGRAM_DONE：1
- FAULT：0
- OTHER_ERRORS：0
- SB_ERRORS：0
- 仿真结束时间：8660 ns

结果：ALL TESTS PASSED

证据：
docs/pipeline_cpu/evidence/v09_stage3_fpga_cpu_pass.png

说明：本次通过的是 V0.9 FPGA CPU 包装模块的行为仿真，
不等于 EGO1 实际下载运行通过。

## Vivado 证据

保留结果截图、仿真日志、`report_compile_order`（Missing instances 应为空），并在完成后记录具体周期数、Cache 命中/缺失数。需要注意：本测试通过仍不能证明 EGO1 Bitstream 下载成功或板上电气配置正确。
