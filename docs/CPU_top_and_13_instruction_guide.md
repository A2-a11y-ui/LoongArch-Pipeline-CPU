# 第七阶段｜正式单周期 CPU 入口 + B 组 13 指令专项验收（V0.1）

> **适用环境**：Vivado 2019.1 / Verilog-2001 / LoongArch-Pipeline-CPU。当前是已验证 18 指令候选架构的**正式集成入口版本**，并非已经达到课程的 ≥25 条指令目标，也不是五级流水线、FPGA 最终验收版本。

## 文件清单

| 文件 | 目标位置 | Vivado 分组 | 说明 |
|---|---|---|---|
| `cpu_top.v` | `rtl/common/cpu_top.v` | Design Sources | 由通过 397 项的 `cpu_top_candidate.v` 派生，实例化统一 `decoder_v2`，并提供 IMEM_INIT_FILE 参数；不改候选原文件 |
| `tb_13_instructions.v` | `tb/tb_13_instructions.v` | Simulation Sources | **64 条真实机器码 + 1 条非法指令**；涵盖你负责的 13 个 opcode 类别，逐条对照独立的预期寄存器及存储器结果 |
| `tb_cpu_top_smoke.v` | `tb/tb_cpu_top_smoke.v` | Simulation Sources | 将之前 397 检查项的整机回归用例原样迁移到正式 `cpu_top`，确保整理过程中原行为没有变化 |
| `13_instruction_vectors.csv` | `docs/13_instruction_vectors.csv` | 不需加入 Vivado | 可审计的每条机器码、PC、操作名及期望结果 |

## 代码依赖与状态

保持已经通过测试、且**仅各含一个同名模块**的现有文件：

- `rtl/common/decoder_v2.v`（当前 18 条指令统一译码器；与队员 A 后续正式 decoder.v V1.2 区分）
- `rtl/common/pc_reg.v`（队员 A 正式版）
- `rtl/common/regfile.v`（队员 A 正式版）
- `rtl/alu_branch/alu.v`（队员 A 正式版）
- `rtl/alu_branch/branch_unit.v`（队员 A 正式版）
- `rtl/memory_cache/imm_gen.v`（你的 V2）
- `rtl/memory_cache/imem.v`、`dmem.v`、公共 `cpu_defs.vh`

如这些模块的实际项目路径略有不同，以你本机仓库为准。务必移除临时同名 `regfile_reference.v` 和 `pc_reg_reference.v` 的**Vivado 工程引用**，无需删除备份。

## Vivado 2019.1 操作步骤

1. 将 `cpu_top.v` 复制到 `D:\CPU_Project\LoongArch-Pipeline-CPU\rtl\common\`，不覆盖 `cpu_top_candidate.v`。
2. 将两个 `tb_*.v` 文件放在仓库 `tb` 目录；将 CSV 放在 `docs`。
3. 在 **Add Sources → Add or Create Design Sources → Add Files** 中加入 `cpu_top.v`（如已加入则跳过）。
4. 在 **Add Sources → Add or Create Simulation Sources → Add Files** 中加入 `tb_13_instructions.v` 和 `tb_cpu_top_smoke.v`。
5. 右键 **`tb_13_instructions` → Set as Top**，点击 **Run Simulation → Run Behavioral Simulation**。
6. 核对 Tcl Console：`Committed instructions = 65`、`Instruction families covered = 13`、`Total errors = 0`、`ALL TESTS PASSED`。
7. 右键 **`tb_cpu_top_smoke` → Set as Top**，再次运行仿真。预期 `Committed instructions = 28`、`Total checks = 397`、`Total errors = 0`。
8. 保存两次仿真的波形和包含末尾统计的 Tcl Console 截图，后续作为个人 13 条指令验收和正式 CPU 迁移验收证据。

Vivado 默认 Behavioral Simulation 的模拟时间通常是 1000ns。该 13 指令测试预计在约 710ns 内结束。如时间设置被改小，使用 **Run All** 直到出现 `$finish`；不要只凭运行时间判断通过。

## 13 指令测试详细覆盖

13 种：`AND`、`OR`、`NOR`、`XOR`、`ANDI`、`ORI`、`XORI`、`SLLI.W`、`SRLI.W`、`SRAI.W`、`LD.W`、`ST.W`、`LU12I.W`。

本测试不只是纯译码：每条真实 32 位机器码都经过 `PC -> IMEM -> Decoder -> RegFile/ImmGen -> ALU -> DMEM -> writeback`，检查当前 PC、机器码、指令有效性、reg/mem 写使能、下一 PC、写回数据以及**时钟之后的真实寄存器/存储器状态**。

边界与组合：全 0、全 1、高符号位、12 位立即数 0/0x7FF/0x800/0xFFF、移位 0/1/4/31、LU12I 0/1/0x80000/0xFFFFF、正负 LD/ST 偏移（包括 -128）、r0 写保护、非法指令无写回、同一源/目的寄存器、连续相关指令、5 个完整停顿时钟周期。

**测试约束**：内存读取使用本项目现有 1 KiB 组合读 `dmem`；地址合法且 4 字节对齐。所有存储地址在 0~1023 范围；本轮**不**宣称覆盖存储器越界保护、硬件异常或完整数据冒险处理。

`tb_13_instructions.v` 使用层次化访问写入 `dut.u_imem.mem[]` 并读取 `dut.u_regfile.regs[]`、`dut.u_dmem.mem[]`，**仅用于仿真**，不应综合到 FPGA；项目当前正式寄存器堆确实使用 `regs` 作为内部数组名。如果 A 后续修改其内部存储器变量名称，需要更新这些测试探针，不影响 CPU 顶层接口。

## 与队员 A 的公共接口协调

当前 `cpu_top.v` 采用 `decoder_v2` 而不是覆盖 `rtl/common/decoder.v`，这是**有意保留稳定基线**。待 A 提交并双方审核正式 Decoder V1.2 时：

1. 确认两版的完整端口及控制语义一致：`branch_type[2:0]`、`imm_sel[2:0]`、`wb_sel[1:0]`、`reg_write`、`mem_write`、`rs1_used`、`rs2_used`、`valid` 等。
2. 把 `cpu_top.v` 中 `decoder_v2 u_decoder (...)` 改为正式 `decoder u_decoder (...)`，或按双方一致的模块命名，且工程内每一模块名只有一个定义。
3. 先重新执行本次 65 条程序、397 项回归，再补充至少 7 种指令的新测试；不能把“65 次执行”误读成“65 种指令”。
4. 单周期稳定后，才开始 IF/ID、ID/EX、EX/MEM、MEM/WB 寄存器和 Forwarding/Stall/Flush/I-Cache。

## 验证记录与重要说明

- 本次交付在此运行环境下进行了**Python 参考语义模型的 65 条向量一致性检查**，以及对候选顶层的结构差异检查。
- **未运行 Vivado 或 Verilog 仿真器**，实际是否通过仍以你的 Vivado 2019.1 Tcl Console 输出为准。
- 你已经实测通过的 397 项属于 `cpu_top_candidate.v`；新 `cpu_top` 的回归目标是保持相同结果，但在你本机重新验证前不能声称已通过。
