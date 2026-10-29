# 五级流水线 CPU V0.2 — Forwarding 回归测试计划

> 基准：A 的 `feature/pipeline-cpu-integration` 分支与正式 `rtl/common/forwarding_unit.v`、`rtl/common/decoder.v`。编写时远程尚未发布 `rtl_test_only/pipeline_cpu_core_v02.v`。**本包不是声称已经跑通 V0.2 的实验结果。**

## 文件

| 文件 | 功能 | 现在可运行？ |
|---|---|---|
| `tb/pipeline_cpu/tb_forwarding_unit_v02.v` | 正式 Forwarding Unit 的 27 场景独立检测（108 项信号检查） | **是**，只依赖 `rtl/common/forwarding_unit.v` |
| `tb/pipeline_cpu/programs/forwarding_v02.mem` | 33 条 32 位真实 LoongArch 机器码，连续 RAW 依赖、不插空拍 | **可用于后续 V0.2** |
| `tb/pipeline_cpu/tb_pipeline_forwarding_v02.v` | V0.2 整机写回对账（32 次正常提交，1 次 r0 不提交） | **需等 A 正式 V0.2 顶层** |
| `docs/pipeline_cpu/forwarding_v02_program_map.csv` | 每条机器码 PC、编码、期望目标寄存器与数据对照 | 是 |

## 重要边界

1. 当前 V0.1 顶层没有 Forwarding；它不应通过这套连续相关测试。**不能把失败归咎于已冻结的 V0.1 设计。**
2. 整机 Testbench 目前默认 `pipeline_cpu_core_v02`，只连接 V0.1 已明确的 `clk/rst/if_valid/if_pc/if_inst/wb_commit_valid/wb_commit_pc/wb_commit_rd/wb_commit_data` 端口。如果 A 的 V0.2 顶层改名，可修改源代码顶部 `CPU_V02_TOP` 宏；如果增加了 IF ready/valid、Stall、提交握手，必须先适配驱动、不能简单逐拍无条件送指令。
3. `forward_a / forward_b` 的编码：`00`=原寄存器，`01`=MEM/WB，`10`=EX/MEM；较新 EX/MEM 未就绪时 `wait_a/wait_b=1`，不能错误取用较旧 WB 值。
4. 指令起点 `0x00001000`，每条有效机器码 PC 加 4；33 条输入，共 32 条正常提交；第 17 条写 r0，应被屏蔽。程序没有 Load/Store、Branch，后续阶段单独验证。
5. 本整机回归假定**单周期接收外部 IF 指令、WB 逐周期可观察**。如 V0.2 未支持反压，这个假设与 V0.1 一致。仿真结束由 `$finish` 控制，通常不用在完成后再次 `run all`。

## 使用说明：第一轮（现在可执行）

1. GitHub Desktop 当前分支是 `feature/pipeline-forwarding-verification`，将本包对应 `tb/`、`docs/` 目录合并到你本地的 `D:\CPU_Project\LoongArch-Pipeline-CPU`。
2. Vivado 2019.1 依次 **Add Sources → Add or Create Simulation Sources**，加入 `tb/pipeline_cpu/tb_forwarding_unit_v02.v`，并确保 `rtl/common/forwarding_unit.v` 已在 Design Sources 中。
3. 设置仿真 Top：

   ```tcl
   set_property top tb_forwarding_unit_v02 [get_filesets sim_1]
   report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
   ```

4. 确认 `Missing instances: <empty>`，运行 **Run Behavioral Simulation**；如果 Vivado 已显示结果就不必再次执行 `run all`。
5. 预期 `cases=27 checks=108 errors=0` 与 `ALL TESTS PASSED`，这是**待实测目标**。

## 第二轮（A 发布 V0.2 顶层之后）

1. 请 A Push `pipeline_cpu_core_v02.v` 到集成分支，并确认是否保持上文所列 9 个 V0.1 外部端口，以及是否有 `if_ready`、IF Stall 或 WB 提交握手。
2. 不要直接把 A 的 integration 分支内容覆盖到 verification；采用 GitHub Desktop 的 **Branch → Merge into current branch** 将最新 integration 安全合入你的 verification。
3. 加入 CPU V0.2 顶层的正式 Verilog 文件、`tb/pipeline_cpu/tb_pipeline_forwarding_v02.v` 和各个已有寄存器/Decoder/RegFile/ImmGen/ALU 等模块。
4. 确认 `forwarding_v02.mem` 绝对路径与工程路径一致。可在 TB 中修改 `parameter MEM_FILE`；如果 `.mem` 找不到，TB 会报告错误。
5. Tcl Console：

   ```tcl
   set_property top tb_pipeline_forwarding_v02 [get_filesets sim_1]
   report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
   ```

6. 仿真应验证 `32/32` 次写回、零断言错误，无 r0 提交。**只有实测通过后才能在 PR 写 `ALL TESTS PASSED`。**

## 检查覆盖

- EX/MEM 前递、MEM/WB 前递、双源混合前递
- 连续 3 级 RAW 链、同一目的寄存器多次覆盖且最新优先
- `ADDI.W` 立即数运算的 A 操作数前递
- r0 读操作与写保护
- 有符号算术移位、SLT / SLTU、AND / OR / XOR / NOR
- 每次写回的 PC、目的寄存器、32 位结果逐项对照；无额外提交

## 版本保护

不更改 `pipeline_cpu_core_v01.v`、CPU27 单周期 CPU、V0.7/V0.8/V0.9 I-Cache/Adapter/PC Controller 或 A 的正式 Forwarding RTL。
