# Decoder V2 与单周期 CPU 整合规范（待双方审核）

## 本次目标

将已验证的 13 条基础指令与 BEQ、BNE、B、BL、JIRL 5 条分支指令合并为**一个**译码器。当前采用独立模块名 `decoder_v2`，不修改现有 `decoder.v` 或已经通过 576 ns 的 `branch_cpu_stage5.v`。

## 信号约定

| 信号 | 位宽 | 用途 |
|---|---:|---|
| `inst` | 32 | 输入机器指令 |
| `rs1_addr`, `rs2_addr`, `rd_addr` | 各5 | 寄存器地址 |
| `rs1_used`, `rs2_used` | 各1 | 有效源寄存器标记，供后续冒险检测 |
| `alu_op` | 4 | 原 `cpu_defs.vh` ALU 控制码 |
| `imm_sel` | 3 | `imm_gen` 选择：0..4 原格式，5 offs16，6 offs26，7 保留 |
| `alu_src_imm` | 1 | ALU B 输入选择 |
| `reg_write` | 1 | 指令需要写回（由 `step_en`, `rst`, `valid` 等在顶层门控） |
| `mem_read`, `mem_write` | 各1 | LD.W/ST.W 访存功能 |
| `branch_type` | 3 | NONE=0, BEQ=1, BNE=2, B=3, BL=4, JIRL=5 |
| `wb_sel` | 2 | `00` ALU, `01` MEM, `10` PC+4, `11` 保留 |
| `wb_sel_mem` | 1 | 为旧模块保留的兼容别名；仅 LD.W 为1 |
| `valid` | 1 | 已支持指令标记；非法指令必须关闭所有写使能 |

## 需要共同确认的关键细节

1. `BEQ`、`BNE`：第一源来自 `rj=inst[9:5]`，第二源来自 `rd=inst[4:0]`，**无写回**。
2. `ST.W`：第二源寄存器也来自 `rd=inst[4:0]`，存入 `dmem.wdata`；**无写回**。
3. `BL`：无源寄存器，`rd_addr=5'd1`，`reg_write=1`，`wb_sel=2'b10`。
4. `JIRL`：使用 `rj` 作为目标基址；写回 `inst[4:0]` 指定的寄存器，`wb_sel=2'b10`。
5. `imm_gen` V2 输出已经左移2位并符号扩展；`branch_unit` 只计算 `pc+imm` 或 `rs1+imm`，不得再次移位。
6. `decoder_v2` 是纯组合逻辑，不含时钟、PC+4、stall、flush。`redirect` 取自 `branch_unit`。单周期顶层的 PC 在上升沿跳转，分支本条指令若 BL/JIRL 同时写入返回地址。
7. 旧版 `decoder.v` 的**全部原端口都保留**；新增 `branch_type` 和 `wb_sel`。旧版有效 `ST.W` 的 `rd_addr` 输出仍保留低5位，仅供查看，不表示写寄存器。
8. 现有 `dmem` 为异步读、同步写；本版本仅是单周期功能验证模型。硬件实现需另行评估对齐异常、同步 BRAM 推断及指令 ROM 初始化。

## 已实现 / 未实现

- 已有：13 基础 + 5 分支 = 18 条指令（**不能宣称满足课程要求的至少25条**）。
- V2 新增：统一分支译码和三路写回选择。
- 尚需：队员 A 的其他算术/分支补充指令、单周期正式 `cpu_top.v`、五级流水线、Forwarding/Stall/Flush、I-Cache 及硬件综合测试。

## 当前阶段集成流程

`pc_reg → imem → decoder_v2 → regfile/imm_gen → ALU/branch_unit/dmem → wb_sel → regfile`

`cpu_top_candidate.v` 只是统一译码器的可运行候选版本；接口对齐旧 `branch_cpu_stage5`，便于用原阶段5测试程序复测。测试通过、A/B审核后，才可将候选版本整理为正式 `cpu_top.v`。
