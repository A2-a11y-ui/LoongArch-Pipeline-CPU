# CPU 五级流水线 V0.1：独立算术写回测试计划

## 目的与边界

- 使用队员 A 的正式 `pipeline_cpu_core_v01` 顶层，外部输入 IF(valid, PC, inst)。
- 独立加载**真实 LoongArch 32 位机器码**（来自仓库 `rtl/common/decoder.v` 的解码常量）。
- 检查真实 Decoder/RegFile/ALU/四组流水线寄存器的 WB 事件是否按顺序产生正确的 PC、rd 和 data。
- **不是** Cache、Forwarding、Branch、Load/Store、多周期反压或完整 27 指令验收。
- A 的分支 `feature/pipeline-cpu-integration` 在制包时尚未能从 GitHub 读取；所以这些文件**未在实际 V0.1 CPU 顶层上仿真验证**，不能据此宣称通过。

## 文件

- `tb/pipeline_cpu/programs/arithmetic_basic.mem`：每行 8 位十六进制机器码，**共 138 个字**；每条实际指令后插入 5 个 `00000000`（IF valid=0）作为流水线间隔。
- `tb/pipeline_cpu/tb_pipeline_cpu_basic.v`：独立时钟、同步复位、IF 驱动、WB 计分板。
- 本文件：测试目的、结果表和 Vivado 操作。

## 接口假设（需要与 A 最终版核对）

```verilog
pipeline_cpu_core_v01 dut (
  .clk(clk), .rst(rst),
  .if_valid(if_valid), .if_pc(if_pc), .if_inst(if_inst),
  .wb_commit_valid(wb_commit_valid),
  .wb_commit_pc(wb_commit_pc),
  .wb_commit_rd(wb_commit_rd),
  .wb_commit_data(wb_commit_data)
);
```

- IF 输入每个时钟上升沿无条件采样，当前尚无 IF ready/hold 端口。
- 送入的 `00000000` 仅表示一个**无效 IF 周期**，Testbench 把 `if_valid` 置 0；不是在 CPU 内执行 NOP。
- 有效指令间隔 5 个周期，以规避尚未实现的 RAW 冒险；如果 A 的实际数据通路有不同的推进/提交时序，以实际 RTL 为准调整，不能简单删掉失败检查。
- 每一次真实寄存器写回输出一次 `wb_commit_valid=1`；r0 目标和不支持的机器码不得产生写回事件。
- Testbench 使用不含执行延迟假设的**提交顺序计分板**，比较 PC、rd、data，另检查总提交数量和 r0 禁写。

## 机器码和结果

所有机器码均按现有 `decoder.v` 的掩码和指令编码生成（3R：op | rk<<10 | rj<<5 | rd；I12：op | (imm12<<10) | rj<<5 | rd；移位立即数：op | shamt<<10 | rj<<5 | rd）。

| # | 提交 PC | 指令类型 | 目标 | 预期写回数据 |
|---|---|---|---|---|
| 1 | 0x00001000 | ADDI | r1 | `0x00000005` |
| 2 | 0x00001018 | ADDI | r2 | `0x00000008` |
| 3 | 0x00001030 | ADDI | r3 | `0xFFFFFFFC` |
| 4 | 0x00001048 | ADDI | r4 | `0x00000001` |
| 5 | 0x00001060 | ADDI | r5 | `0x0000001F` |
| 6 | 0x00001078 | ADD | r10 | `0x0000000D` |
| 7 | 0x00001090 | SUB | r11 | `0x00000003` |
| 8 | 0x000010A8 | AND | r12 | `0x00000000` |
| 9 | 0x000010C0 | OR | r13 | `0x0000000D` |
| 10 | 0x000010D8 | XOR | r14 | `0x0000000D` |
| 11 | 0x000010F0 | NOR | r15 | `0xFFFFFFF2` |
| 12 | 0x00001108 | SLL | r16 | `0x0000000A` |
| 13 | 0x00001120 | SRL | r17 | `0x0000000F` |
| 14 | 0x00001138 | SRA | r18 | `0xFFFFFFFE` |
| 15 | 0x00001150 | ADDI | r19 | `0x00000003` |
| 16 | 0x00001168 | ANDI | r20 | `0x0000000F` |
| 17 | 0x00001180 | ORI | r21 | `0x00000015` |
| 18 | 0x00001198 | XORI | r22 | `0x0000000B` |
| 19 | 0x000011B0 | SLLI | r23 | `0x00000014` |
| 20 | 0x000011C8 | SRLI | r24 | `0x00000003` |
| 21 | 0x000011E0 | SRAI | r25 | `0xFFFFFFFE` |

其他输入：写 `r0` 的 ADD.W（应不提交）、`0xFFFFFFFF` 未识别指令（应不提交）。总预期有效写回数 **21**。

## Vivado 2019.1 操作

1. GitHub Desktop 切换到你的 `feature/pipeline-cpu-verification` 分支，把以上 3 个文件放到项目相同路径。
2. **等队员 A Push 了 `feature/pipeline-cpu-integration` 后**，先确认其 `pipeline_cpu_core_v01.v` 实际模块和端口。通过团队约定的集成 PR、合并或直接把指定版本文件引用进独立仿真工程，**不要直接覆盖 `main` 的稳定 CPU27**。
3. Vivado：`Add Sources → Add or Create Simulation Sources` 添加 `tb_pipeline_cpu_basic.v`。CPU 顶层和它依赖的正式模块加入工程设计源或可用于仿真的源集。
4. 设置 Simulation Top 为 `tb_pipeline_cpu_basic`，并运行：

```tcl
report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
```

5. `Missing instances` 应为空。关闭旧仿真，重新 `Run Behavioral Simulation`，执行 `run all`。
6. 默认自动尝试仓库路径、Vivado 常见仿真路径，以及 `D:/CPU_Project/LoongArch-Pipeline-CPU/...`。若仍提示找不到 `.mem` 文件，请将其绝对路径替换到 TB 中 `program_path` 默认值，或在仿真配置里添加 `+PROGRAM=D:/.../arithmetic_basic.mem`。
7. 观察 `PASS commit[...]`、`Expected commits=21`、`errors=0`、`ALL TESTS PASSED`。如失败，请保留全部 FAIL、simulate.log、编译顺序。

## 当前验证状态

- 生成时已静态核查机器码符合仓库 `decoder.v` 对应操作码掩码，预期数据由独立计算给出。
- **未**执行真实 `pipeline_cpu_core_v01` 的 Vivado 仿真；未承诺结果一定通过。
- 请勿在 A 的顶层尚未合并/确认之前提交称为“已通过”的测试证据。
