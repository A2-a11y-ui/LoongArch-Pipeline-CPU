# V0.9 指令清单与独立验证计划（第一阶段）

**工程**：LoongArch-Pipeline-CPU  
**建议分支**：`test/pipeline-v09-verification`  
**数据来源**：本次上传的 `decoder(5).v`、`mdu_decode_v08.v`、`mdu_iterative.v`、`v08_mdu_interface.md`  
**状态**：源码静态检查与测试向量生成完成；**尚未在 V0.9 FPGA CPU 上实际仿真/验收**。

## 一、指令统计与统计口径

- `decoder(5).v` 定义 **22 条普通 ALU/立即数/访存指令 + 5 条分支/跳转指令 = 27 条**。
- `mdu_decode_v08.v` 额外识别 **7 条 MDU 指令**。
- 两组匹配值没有重复：**总计 34 条不同的指令译码类型**，超过“至少 25 条”的数量门槛。
- **不能直接据此声称 V0.9 CPU 已支持并通过 34 条**。新顶层须同时连接两个译码器、覆盖 MDU 的译码控制、支持正确执行，还须有逐条 WB/Store/PC 的实际回归数据。
- 当前 `decoder.v` 本身**不会**将 7 条 MDU 指令设置为 `valid=1`；只有 CPU 正确叠加辅助译码结果，它们才会成为可执行指令。这是接入 FPGA 顶层时的首要核查点。

| 分类 | 条数 |
|---|---:|
| ALU三寄存器 | 11 |
| 立即数ALU | 5 |
| 立即数移位 | 3 |
| 高位立即数 | 1 |
| 访存 | 2 |
| 分支跳转 | 5 |
| MDU乘除法 | 7 |
| **合计** | **34** |

## 二、34 条指令源代码级清单与独立示例

**注意**：示例一律是**相互独立**的定向向量，`PC=0x00001000`，每条指令的寄存器初始值及 RAM 前置条件都以对应 CSV 行为准，不能把下面 34 个机器码直接串起来当成完整可执行 CPU 程序。对应的初始状态请查 `v09_instruction_inventory.csv`。

- 通用 3R 示例：`r1=12, r2=5, rd=r3`；MDU 的 3 位 `op` 是模块内部控制码，不是机器码。
- 带符号 I12 示例按 LA32 的 12 位二补码编码；移位立即数使用位 `inst[14:10]`。
- 分支/跳转采用 `PC=0x1000` 的示例，目标 PC 为测试预期，仍需由 V0.9 实际验证。

| # | 指令 | 类别 | 匹配掩码 | 匹配值 | 示例完整机器码 | 独立预期结果 |
|---:|---|---|---|---|---|---|
| 1 | `ADD.W` | ALU三寄存器 | `0xFFFF8000` | `0x00100000` | `0x00100823` | WB: r3=0x00000011 |
| 2 | `SUB.W` | ALU三寄存器 | `0xFFFF8000` | `0x00110000` | `0x00110823` | WB: r3=0x00000007 |
| 3 | `SLT` | ALU三寄存器 | `0xFFFF8000` | `0x00120000` | `0x00120823` | WB: r3=0x00000000 |
| 4 | `SLTU` | ALU三寄存器 | `0xFFFF8000` | `0x00128000` | `0x00128823` | WB: r3=0x00000000 |
| 5 | `SLL.W` | ALU三寄存器 | `0xFFFF8000` | `0x00170000` | `0x00170823` | WB: r3=0x00000180 |
| 6 | `SRL.W` | ALU三寄存器 | `0xFFFF8000` | `0x00178000` | `0x00178823` | WB: r3=0x00000000 |
| 7 | `SRA.W` | ALU三寄存器 | `0xFFFF8000` | `0x00180000` | `0x00180823` | WB: r3=0x00000000 |
| 8 | `NOR` | ALU三寄存器 | `0xFFFF8000` | `0x00140000` | `0x00140823` | WB: r3=0xFFFFFFF2 |
| 9 | `AND` | ALU三寄存器 | `0xFFFF8000` | `0x00148000` | `0x00148823` | WB: r3=0x00000004 |
| 10 | `OR` | ALU三寄存器 | `0xFFFF8000` | `0x00150000` | `0x00150823` | WB: r3=0x0000000D |
| 11 | `XOR` | ALU三寄存器 | `0xFFFF8000` | `0x00158000` | `0x00158823` | WB: r3=0x00000009 |
| 12 | `ADDI.W` | 立即数ALU | `0xFFC00000` | `0x02800000` | `0x02BFF423` | WB: r3=0x00000009 |
| 13 | `SLTI` | 立即数ALU | `0xFFC00000` | `0x02000000` | `0x023FF423` | WB: r3=0x00000000 |
| 14 | `ANDI` | 立即数ALU | `0xFFC00000` | `0x03400000` | `0x03403C23` | WB: r3=0x0000000C |
| 15 | `ORI` | 立即数ALU | `0xFFC00000` | `0x03800000` | `0x03803C23` | WB: r3=0x0000000F |
| 16 | `XORI` | 立即数ALU | `0xFFC00000` | `0x03C00000` | `0x03C03C23` | WB: r3=0x00000003 |
| 17 | `SLLI.W` | 立即数移位 | `0xFFFF8000` | `0x00408000` | `0x00408823` | WB: r3=0x00000030 |
| 18 | `SRLI.W` | 立即数移位 | `0xFFFF8000` | `0x00448000` | `0x00448823` | WB: r3=0x00000003 |
| 19 | `SRAI.W` | 立即数移位 | `0xFFFF8000` | `0x00488000` | `0x00488823` | WB: r3=0x00000003 |
| 20 | `LU12I.W` | 高位立即数 | `0xFE000000` | `0x14000000` | `0x142468A3` | WB: r3=0x12345000 |
| 21 | `LD.W` | 访存 | `0xFFC00000` | `0x28800000` | `0x28802023` | WB: r3=0x12345678; read addr=0x48 |
| 22 | `ST.W` | 访存 | `0xFFC00000` | `0x29800000` | `0x29803022` | STORE: addr=0x4C; data=0xDEADBEEF; no WB |
| 23 | `BEQ` | 分支跳转 | `0xFC000000` | `0x58000000` | `0x58000C22` | BRANCH: taken; target PC=0x100C; no WB |
| 24 | `BNE` | 分支跳转 | `0xFC000000` | `0x5C000000` | `0x5C000C22` | BRANCH: taken; target PC=0x100C; no WB |
| 25 | `JIRL` | 分支跳转 | `0xFC000000` | `0x4C000000` | `0x4C000C23` | BRANCH+WB: target PC=0x20C; WB r3=0x1004 |
| 26 | `B` | 分支跳转 | `0xFC000000` | `0x50000000` | `0x50000C00` | BRANCH: target PC=0x100C; no WB |
| 27 | `BL` | 分支跳转 | `0xFC000000` | `0x54000000` | `0x54000C00` | BRANCH+WB: target PC=0x100C; WB r1=0x1004 |
| 28 | `MUL.W` | MDU乘除法 | `0xFFFF8000` | `0x001C0000` | `0x001C0823` | WB: r3=0x0000003C |
| 29 | `MULH.W` | MDU乘除法 | `0xFFFF8000` | `0x001C8000` | `0x001C8823` | WB: r3=0x00000000 |
| 30 | `MULH.WU` | MDU乘除法 | `0xFFFF8000` | `0x001D0000` | `0x001D0823` | WB: r3=0x00000000 |
| 31 | `DIV.W` | MDU乘除法 | `0xFFFF8000` | `0x00200000` | `0x00200823` | WB: r3=0x00000002 |
| 32 | `DIV.WU` | MDU乘除法 | `0xFFFF8000` | `0x00210000` | `0x00210823` | WB: r3=0x00000002 |
| 33 | `MOD.W` | MDU乘除法 | `0xFFFF8000` | `0x00208000` | `0x00208823` | WB: r3=0x00000002 |
| 34 | `MOD.WU` | MDU乘除法 | `0xFFFF8000` | `0x00218000` | `0x00218823` | WB: r3=0x00000002 |

## 三、为什么第一批先做“独立 Decoder 测试”

已新增 `tb/pipeline_cpu/tb_v09_decode_inventory.v`，实例化**原有正式 `decoder` 与辅助 `mdu_decode_v08`**，使用 34 条机器码逐条验证：

1. 普通指令的 `valid`、寄存器读/写地址、使用标志、ALU 控制、立即数类型、分支类别、Load/Store/WB 控制。
2. 七条 MDU 指令的 `is_mdu`、内部 `mdu_op` 和 3R 寄存器字段；同时确认它们不会被旧 Decoder 意外当作普通指令。
3. 三个非法字不会错误触发两套译码。
4. 每个字段错误均打印独立 FAIL；错误使用 `$fatal(1,...)` 使自动回归失败退出。

**本项只验证组合译码结果**，不会模拟五级流水线，也不会验证真实运算、分支目标、WB/Store 次数或 FPGA 实机行为。

### Vivado 2019.1 使用步骤

1. 保留原有 `rtl/common/decoder.v` 和 `rtl_test_only/mdu_decode_v08.v` 作为 Design Sources；本包**不提供、不覆盖**这两个模块。
2. 确认 `cpu_defs.vh` 的原有 include 引用在工程中可解析；不修改稳定 Decoder 的 include 行。
3. 加入 `tb/pipeline_cpu/tb_v09_decode_inventory.v` 作为 Simulation Sources。
4. Set as Top：`tb_v09_decode_inventory`，运行 Behavioral Simulation，`run all`。
5. 记录实际 `CASES/CHECKS/ERRORS`。只有真实 Tcl 输出 `ERRORS=0` 和 `ALL TESTS PASSED` 才能把这一项状态改成通过。
6. 执行 `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`，确认 `Missing instances: < empty >`。

## 四、与 B 的 FPGA 新顶层对接时必须核查的接口

- 新顶层的模块名、`clk/rst`、程序初始化方式、板级 Reset/时钟域。
- `wb_commit_valid/pc/rd/data` 是否真实反映**架构写回提交**；`rd=0` 应掩蔽。
- `mem_store_commit_valid/pc/addr/data` 是否真实反映**Store 一次性提交**。
- 五级流水线进度和可见控制：`if_ready`、`branch_redirect`、`load_use_stall`、`mem_stall`、`mdu_start_fire`、`mdu_done`、`mdu_result_fire`。
- I-Cache Miss、DMEM 单 outstanding、MDU `done && !result_ready` 的保持约定是否未变。
- 是否存在仿真专用调试顶层与**可综合 FPGA 顶层**的端口差异；不可用层级探针替代正式对外验收接口。

## 五、第二批独立测试建议（B 顶层接口明确后实现）

| 测试编号 | 关注内容 | 必须对照的独立预期 | 状态 |
|---|---|---|---|
| V09-D01 | 34 条逐条正向执行 | WB PC、rd、data；Store PC/地址/数据；Branch 目标及错误路径 | 未执行 |
| V09-H01 | EX/MEM + MEM/WB 前递 | 连续 RAW 最终数据及提交顺序 | 未执行 |
| V09-H02 | LD.W→ALU/MDU | Load-use 暂停；MDU 启动前取得真 Load 数据 | 未执行 |
| V09-C01 | Branch taken/not-taken | 错误路径 WB/Store 必须为零 | 未执行 |
| V09-M01 | 7 种 MDU、符号边界、除零 | 商/余数/高位乘积与独立数学参考一致 | 未执行 |
| V09-M02 | MDU done + older MEM stall | `done/result` 稳定，`result_ready=0`，释放后恰好提交一次 | 未执行 |
| V09-R01 | MDU busy / pending done Reset | 复位后无幽灵写回，能重启 | 未执行 |
| V09-I01 | I-Cache busy + MEM stall + Redirect | 旧 IF 响应不交付，正确目标恰好取指一次 | 未执行 |
| V09-F01 | FPGA 可综合/实现/时序与 EGO1 | 资源报告、时序报告、实机输出与参考结果比对 | 未执行 |

### MDU 边界黄金结果（延续上传文件中的约定）

| 操作 | 输入 | 黄金结果 |
|---|---|---|
| DIV.W | `0x80000000 / 0xFFFFFFFF` | `0x80000000` |
| MOD.W | `0x80000000 % 0xFFFFFFFF` | `0x00000000` |
| MOD.W | `-13 % 5` | `0xFFFFFFFD` |
| DIV.W / DIV.WU | divisor = 0 | `0xFFFFFFFF`; `div_zero=1` |
| MOD.W / MOD.WU | divisor = 0 | 原被除数；`div_zero=1` |
| MULH.W | `0xFFFFFFFF * 2` | `0xFFFFFFFF` |
| MULH.WU | `0xFFFFFFFF * 2` | `0x00000001` |

除零结果是所上传 `mdu_iterative.v` 的**实现约定**，不等于新增硬件异常机制。

## 六、验收证据与报告口径

- 目前可写：**“根据提供的 Decoder RTL 共识别 34 条不同的指令类型，其中基础 Decoder 27 条、MDU 辅助译码 7 条。”**
- 目前不可写：**“V0.9 已通过 34 条指令整机功能测试”**；V0.9 顶层/整机回归/FPGA 实机结果尚未提供。
- 每个后续 V0.9 测试至少保存：独立机器码、输入/参考结果、实际 Scoreboard 输出、`errors=0` 或完整失败记录、关键波形、Vivado 编译依赖检查。
- 最终 FPGA 报告另外保存：综合利用率、时序收敛、约束/引脚、bitstream、EGO1 上电/复位/运行证据。
