# V0.9 ISA34 全指令整机独立回归测试计划（候选，待 Vivado 实测）

## 实验目标与版本

- 使用 PR #41 合并后的正式 `pipeline_cpu_fpga` / `pipeline_cpu_core_v08_mdu_datapath`、优化版 ID/EX 与 Adapter，以及 PR #40 的 `v09_commit_scoreboard.v`。
- **一份独立 ROM 程序** + **一个 Simulation Top**，目标覆盖全部 **34 种 LoongArch** 指令，自动核对完整的 WB、Store、分支结果。
- 当前尚未在 Vivado 2019.1 实测，**不可预先宣布 PASS**；Python 参考模型属于工具生成时的离线自检，不替代 RTL 仿真。
- 不覆盖现有 `fpga_demo.mem`、40 字 Stage3 程序、Smoke Testbench，亦不修改任何正式 RTL。

## 本次生成的程序内容（静态已自检）

- ROM 程序：**61 个机器字**，PC 0x1000 .. 0x10F0，不超过 BRAM 256 字深度。
- 离线参考模拟：有效执行 **56 条**，覆盖 **34/34 种**指令类型；**WB 48** 次、**Store 3** 次，**分支解析 7** 次（实际 Redirect 5 次）、MDU 7 次、访存请求/响应各预计 7 次。
- 故意插入 5 条错误路径毒化指令：按正确控制流全部跳过、不得错误写回 r18。
- 数据含有正负数、符号/无符号比较、逻辑运算、移位、带符号立即数、乘法高低位、除法和余数、Load-use、Store 来源依赖、链接寄存器及目标地址。

## 文件清单

| 文件 | 用途 |
|---|---|
| `tb/pipeline_cpu/tb_v09_isa34_full.v` | 仿真顶层，含黄金参考和覆盖/分支检查 |
| `tb/pipeline_cpu/programs/v09_isa34_full.mem` | 新的 61 字机器码程序 |
| `docs/pipeline_cpu/v09_isa34_golden_reference.csv` | 全部预期 WB、Store、分支的逐笔清单 |
| `docs/pipeline_cpu/v09_isa34_instruction_map.csv` | 全部机器码/PC/指令类型/参考是否实际执行 |

## Vivado 2019.1 操作

1. **先保持原正式工程和上板程序不动**；建议在 `feature/pipeline-cpu-integration` 最新版本下新建测试分支 `test/pipeline-v09-isa34-coverage`，或者先在仓库外试跑。
2. 将 `.v` 放在 `tb/pipeline_cpu/`，`.mem` 放在 `tb/pipeline_cpu/programs/`，两份 `.csv` 放在 `docs/pipeline_cpu/`；只添加 Testbench 到 Simulation Sources，不参与综合。
3. `tb_v09_isa34_full.v` 顶部的 `MEM_FILE` 默认值是 `D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v09_isa34_full.mem`。检查你的实际安装路径，必要时**仅调整 Testbench 参数**。
4. Vivado 中已有正式模块 `pipeline_cpu_fpga.v`、`imem_bram.v`、Cache、MDU、DMEM、Decoder、ImmGen、正式 0.8 datapath 等；尤其要保留优化版 `id_ex_reg.v` / `icache_if_adapter.v`，不得同时引用重复模块。
5. 将 `tb_v09_isa34_full` 设为 **Simulation Top**。先运行 `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`，核实 Missing Instances 为空且无重复模块。
6. `Run Behavioral Simulation`，Tcl Console 运行 `run all`。Testbench 首先逐字对照 DUT 实际加载的 ROM，错误路径或路径不匹配将直接 FAIL；随后核对所有 WB/Store/Branch/MEM/MDU/Load-use/Cache 结果。
7. 只有 Vivado 显示 `TYPES=34/34`、`WB=48/48`、`STORE=3/3`、`BR=7/7`、`OTHER_ERRORS=0`、`SB_ERRORS=0`，以及 `ALL TESTS PASSED`，才能记录通过。
8. 保存真实 Tcl Console 日志和截图，建议证据名 `docs/pipeline_cpu/evidence/v09_isa34_full_pass.png`。如果 FAIL，不要降低 Scoreboard 的检查条件，不要直接改正式 RTL；记录 PC/指令/预期/实际值，先排查测试程序。

## 验证边界

这组新测试着重 **34 种指令的当前 V0.9 FPGA wrapper 整机执行**。它不是 EGO1 板上的 34 指令实物逐条验证，也不能替代 PR #44 的 Flush/Adapter/Reset 专项或此前特定并发边界。关键结构的独立证据仍应从之前的 Testbench 汇总。最终课程报告还需要至少一项**同条件优化前/后**量化性能比较，以及板级 LED 预期与实际值对应记录。

## 本机实测记录（运行后填写）

- Vivado Build/Version：**待填写**
- RTL commit：**待填写**
- Actual WB/Store/Branch/MDU/DMEM/Cache：**待填写**
- Errors：**待填写**
- Conclusion：**NOT TESTED in Vivado**
