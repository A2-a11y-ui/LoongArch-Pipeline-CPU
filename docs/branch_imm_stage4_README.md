# 阶段四：LoongArch 分支立即数扩展（V2）

## 目标

在**保持 `imm_gen(inst[31:0], imm_sel[2:0], imm[31:0])` 原端口不变**的条件下，增加分支16位/26位偏移生成，供队员 A 的 `branch_unit.v` 和公共 `decoder.v` 使用。

## 选择码（新旧对照）

| imm_sel | 描述 | 输出 |
|---|---|---|
| 0 | 无立即数 | 0 |
| 1 | signed 12 (`LD.W/ST.W`) | `{{20{inst[21]}},inst[21:10]}` |
| 2 | unsigned 12 (`ANDI/ORI/XORI`) | `{20'b0,inst[21:10]}` |
| 3 | unsigned 5 (移位) | `{27'b0,inst[14:10]}` |
| 4 | 高20位 (`LU12I.W`) | `{inst[24:5],12'b0}` |
| 5 | signed 16 位分支字节偏移（BEQ/BNE/JIRL） | `{{14{inst[25]}},inst[25:10],2'b0}` |
| 6 | signed 26 位分支字节偏移（B/BL） | `{{4{inst[9]}},inst[9:0],inst[25:10],2'b0}` |
| 7 | 保留 | 0 |

**注意：**`inst[25:10]` 与此前 si12 的 `inst[21:10]` 不同。B/BL 的 26 位偏移分拆储存，必须按 `{inst[9:0],inst[25:10]}` 拼回。两个分支偏移都是已经左移 2 位的有符号“字节偏移”，**分支目标基于当前分支指令 PC**，不是 PC+4：
- BEQ/BNE/B/BL：`target_pc = pc + imm`；
- JIRL：`target_pc = GR[rj] + imm`。

ALU 当前 12 个控制码和 `cpu_defs.vh` 均无需更改。`pc_reg.v` 只保存 PC，不执行分支判断。

## 特别注意：旧 Testbench 需要同步调整

原 `tb_imm_gen.v` 使用选择码 5、6、7 测试“保留 -> 0”。升级以后 **5 和 6 不再保留**，原测试若不修改，就会出现预期不一致。建议保留旧文件作为历史证据，**这轮运行 `tb_imm_gen_branch.v`**，它涵盖了 V1.1 的全部格式，并新增完整分支测试。

## 在 Vivado 2019.1 中操作

1. 先在 GitHub Desktop 确认 `feature/memory` 的最新源码已经提交保存，并在 Windows 中备份原来的 `rtl/memory_cache/imm_gen.v`。
2. 用包里的 `rtl/memory_cache/imm_gen.v` **替换原文件**，不要以另一个模块名添加第二份 `imm_gen`。Vivado 已经指向原文件时，保存覆盖后通常不需要再次 Add Sources。
3. 把 `tb/tb_imm_gen_branch.v` 放进仓库 `tb` 文件夹，选择 `Add Sources -> Add or Create Simulation Sources -> Add Files`，添加它。
4. 右键 `tb_imm_gen_branch` -> `Set as Top`，执行 `Run Behavioral Simulation`。
5. 预期控制台输出：`Total tests = 82`、`Total errors = 0`、`ALL TESTS PASSED`，仿真结束于 82ns。
6. 然后用历史 `tb_datapath_stage1`、`tb_fetch_datapath_stage2`、`tb_pc_fetch_stage3` 按需再跑回归测试，确保原指令仍可执行（原 `tb_imm_gen.v` 的保留码测试需要先修正）。
7. 正式发 PR 前，把新增 `imm_sel=5/6` 约定发给队员 A，等待他确认后共同修改 Decoder。**不要一个人覆盖双方共享的 `decoder.v`**。

## 实验验收与局限

这轮只验证组合立即数生成器，**尚未验证分支跳转的实际 PC 目标、BL/JIRL 的 PC+4 写回、数据冒险与流水线冲刷**；这些必须在后续 `branch_unit` 与公共 CPU 顶层集成后进行。

## 资料

- LoongArch 官方架构手册：https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html
- LLVM LoongArch 指令编码格式定义：https://swiftshader.googlesource.com/SwiftShader.git/+/refs/heads/master/third_party/llvm-16.0/llvm/lib/Target/LoongArch/LoongArchInstrFormats.td
