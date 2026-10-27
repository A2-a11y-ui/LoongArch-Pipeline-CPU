# LoongArch-Pipeline-CPU 指令规格表（队员 B 草稿）

> 文档版本：V0.2（待队员 A、B 共同审核）  
> 目标：32 位 LoongArch 指令子集 CPU  
> 工具：Vivado 2019.1；目标器件 `xc7a35tcsg324-1`  
> 队员 B 分支：`feature/memory`  
> 关联文件：`rtl/common/cpu_defs.vh`、`rtl/memory_cache/imm_gen.v`、`rtl/memory_cache/dmem.v`

**重要说明：** 本文记录当前协作约定和队员 B 的 13 条指令需求。固定机器码、完整匹配掩码及最终译码器接口仍须双方依据官方 LoongArch 文档核对；不得凭经验编造操作码。

---

## 1. 范围与原则

队员 B 负责的 13 条指令：

- 逻辑寄存器指令：`AND`、`OR`、`NOR`、`XOR`
- 逻辑立即数指令：`ANDI`、`ORI`、`XORI`
- 立即数移位指令：`SLLI.W`、`SRLI.W`、`SRAI.W`
- 高位立即数指令：`LU12I.W`
- 访存指令：`LD.W`、`ST.W`

当前已独立完成并通过仿真的模块为 `dmem.v`/`tb_dmem.v` 和 `imm_gen.v`/`tb_imm_gen.v`。模块独立测试通过不等于整机集成测试通过。

共同原则：

1. 指令宽度 32 位，通用寄存器数据宽度 32 位，`r0` 恒为 0。
2. PC 初值暂定 `0x00000000`，顺序执行时 PC 增加 4。
3. 时序逻辑使用时钟上升沿；公共接口规范暂定同步、高电平有效复位。
4. ALU 控制码和 `imm_sel` 都是 CPU 内部控制信号，不是指令机器码。
5. `decoder.v` 由双方共同设计；本文件只记录需求，不代替最终译码器。
6. 固定编码、字段位段和机器码测试值必须以官方 ISA 文档为依据，经过双方复核后再用于译码。
7. 本项目只实现约定的指令子集；未实现指令不得被错误地译码为有效指令。

## 2. 公共 ALU 控制码

以 `rtl/common/cpu_defs.vh` 当前约定为准。

| 宏 | 值 | 含义 |
|---|---:|---|
| `ALU_ADD` | `4'h0` | 32 位加法 |
| `ALU_SUB` | `4'h1` | 32 位减法 |
| `ALU_AND` | `4'h2` | 按位与 |
| `ALU_OR` | `4'h3` | 按位或 |
| `ALU_XOR` | `4'h4` | 按位异或 |
| `ALU_NOR` | `4'h5` | 按位或后取反 |
| `ALU_SLT` | `4'h6` | 有符号小于比较 |
| `ALU_SLTU` | `4'h7` | 无符号小于比较 |
| `ALU_SLL` | `4'h8` | 逻辑左移 |
| `ALU_SRL` | `4'h9` | 逻辑右移 |
| `ALU_SRA` | `4'hA` | 算术右移 |
| `ALU_PASS_B` | `4'hB` | 输出操作数 B |

根据队员 A 的接口确认 V1.1，ADD、SUB、AND、OR、XOR、NOR、PASS_B、SLT、SLTU 已通过现有测试；SLL、SRL、SRA 尚须完成并验证。控制码已定义不代表对应运算已实现。

## 3. 立即数选择码

按双方接口确认 V1.1：

| `imm_sel` | 名称 | 规则 | 用途 |
|---:|---|---|---|
| `3'd0` | 无立即数 | 输出 `32'b0` | 寄存器-寄存器指令 |
| `3'd1` | 有符号 12 位 | `{{20{inst[21]}}, inst[21:10]}` | `LD.W`、`ST.W` 地址偏移 |
| `3'd2` | 无符号 12 位 | `{20'b0, inst[21:10]}` | `ANDI`、`ORI`、`XORI` |
| `3'd3` | 无符号 5 位 | `{27'b0, inst[14:10]}` | `SLLI.W`、`SRLI.W`、`SRAI.W` |
| `3'd4` | 高 20 位构造 | `{inst[24:5], 12'b0}` | `LU12I.W` |
| `3'd5`–`3'd7` | 保留 | 当前版本输出 0 | 后续共同扩展 |

`imm_sel` 由公共译码器生成。`imm_gen` 只根据 `inst` 和 `imm_sel` 产生 32 位立即数，不负责识别完整指令。

## 4. 指令字段（正式译码前须复核）

以下是当前设计草案中的字段位置；最终应由双方对照官方指令格式确认固定编码字段和匹配掩码。

| 指令格式/类别 | 字段 | 预期位段 | 说明 |
|---|---|---|---|
| 3R 逻辑指令 | `rk` | `inst[14:10]` | 第二源寄存器 |
| 3R 逻辑指令 | `rj` | `inst[9:5]` | 第一源寄存器 |
| 3R 逻辑指令 | `rd` | `inst[4:0]` | 目的寄存器 |
| 2RI12 指令 | `ui12`/`si12` | `inst[21:10]` | 立即数字段 |
| 2RI12 指令 | `rj` | `inst[9:5]` | 源寄存器/基址寄存器 |
| 2RI12 指令 | `rd` 字段 | `inst[4:0]` | `LD.W` 为目的寄存器；`ST.W` 为待存数据寄存器字段 |
| 移位立即数指令 | `ui5` | `inst[14:10]` | 无符号移位量 0–31 |
| 移位立即数指令 | `rj` | `inst[9:5]` | 待移位数据寄存器 |
| 移位立即数指令 | `rd` | `inst[4:0]` | 目的寄存器 |
| `LU12I.W` | `si20` | `inst[24:5]` | 放在结果高 20 位 |
| `LU12I.W` | `rd` | `inst[4:0]` | 目的寄存器 |

### 4.1 已整理的四条逻辑寄存器指令编码（待队员 A 复核）

以下 `Match` 与 `Mask` 用于说明如何识别指令。比较时使用：

```verilog
(inst & MASK) == MATCH
```

| 指令 | Match（固定编码值） | Mask（匹配掩码） |
|---|---:|---:|
| `NOR` | `32'h00140000` | `32'hFFFF8000` |
| `AND` | `32'h00148000` | `32'hFFFF8000` |
| `OR` | `32'h00150000` | `32'hFFFF8000` |
| `XOR` | `32'h00158000` | `32'hFFFF8000` |

这些值来自本轮指令编码整理，**合并最终译码器前仍须队员 A 对照官方 LoongArch 指令手册复核**。当前只列出这四条指令；其余九条指令的 Match/Mask 尚未填写，不能据此认为 13 条指令的编码已经全部确认。

三寄存器格式字段分布：

| 位段 | 字段 | 说明 |
|---|---|---|
| `inst[31:15]` | 固定编码字段 | 用于指令匹配 |
| `inst[14:10]` | `rk` | 第二源寄存器编号 |
| `inst[9:5]` | `rj` | 第一源寄存器编号 |
| `inst[4:0]` | `rd` | 目的寄存器编号 |

例如，识别 `AND` 的比较形式为：

```verilog
if ((inst & 32'hFFFF8000) == 32'h00148000) begin
    // AND 指令
end
```

掩码 `32'hFFFF8000` 保留高 17 位固定编码，忽略低 15 位的三个寄存器编号。该代码仅演示匹配方式，不是完整 `decoder.v`。


## 5. 队员 B 的 13 条指令控制需求表

表中控制需求是功能层面的草案。`RegWrite`、`MemRead`、`MemWrite`、操作数选择信号的最终命名、位宽和默认值须由双方共同确认。

| 指令 | 源操作数需求 | `imm_sel` | `alu_op` | 寄存器写回 | 读存储器 | 写存储器 | 写回来源 |
|---|---|---:|---|---|---|---|---|
| `AND` | `rj`、`rk` | 0 | `ALU_AND` | 是 | 否 | 否 | ALU |
| `OR` | `rj`、`rk` | 0 | `ALU_OR` | 是 | 否 | 否 | ALU |
| `NOR` | `rj`、`rk` | 0 | `ALU_NOR` | 是 | 否 | 否 | ALU |
| `XOR` | `rj`、`rk` | 0 | `ALU_XOR` | 是 | 否 | 否 | ALU |
| `ANDI` | `rj`、零扩展 `ui12` | 2 | `ALU_AND` | 是 | 否 | 否 | ALU |
| `ORI` | `rj`、零扩展 `ui12` | 2 | `ALU_OR` | 是 | 否 | 否 | ALU |
| `XORI` | `rj`、零扩展 `ui12` | 2 | `ALU_XOR` | 是 | 否 | 否 | ALU |
| `SLLI.W` | `rj`、`ui5` | 3 | `ALU_SLL` | 是 | 否 | 否 | ALU |
| `SRLI.W` | `rj`、`ui5` | 3 | `ALU_SRL` | 是 | 否 | 否 | ALU |
| `SRAI.W` | `rj`、`ui5` | 3 | `ALU_SRA` | 是 | 否 | 否 | ALU |
| `LU12I.W` | 构造后的立即数 | 4 | `ALU_PASS_B`（按当前分工约定） | 是 | 否 | 否 | ALU B/立即数 |
| `LD.W` | 基址 `rj`、有符号 `si12` | 1 | `ALU_ADD` | 是 | 是 | 否 | 存储器读数据 |
| `ST.W` | 基址 `rj`、有符号 `si12`、待存数据寄存器 | 1 | `ALU_ADD` | 否 | 否 | 是 | 不适用 |

### 5.1 逻辑寄存器指令

- `AND`：`GR[rd] = GR[rj] & GR[rk]`
- `OR`：`GR[rd] = GR[rj] | GR[rk]`
- `NOR`：`GR[rd] = ~(GR[rj] | GR[rk])`
- `XOR`：`GR[rd] = GR[rj] ^ GR[rk]`

使用两个寄存器操作数，结果写入 `rd`，不使用立即数。

### 5.2 逻辑立即数指令

- `ANDI`：`GR[rd] = GR[rj] & ZeroExtend(ui12, 32)`
- `ORI`：`GR[rd] = GR[rj] | ZeroExtend(ui12, 32)`
- `XORI`：`GR[rd] = GR[rj] ^ ZeroExtend(ui12, 32)`

`imm_sel=3'd2`，ALU A 输入为 `GR[rj]`，B 输入为零扩展后的立即数，结果写回 `rd`。

### 5.3 立即数移位指令

- `SLLI.W`：对 `GR[rj][31:0]` 逻辑左移 `ui5` 位。
- `SRLI.W`：对 `GR[rj][31:0]` 逻辑右移 `ui5` 位。
- `SRAI.W`：对 `GR[rj][31:0]` 算术右移 `ui5` 位。

`imm_sel=3'd3`，ALU A 输入是待移位数据，B 输入低 5 位是移位量。移位量为无符号数，范围 0–31。`SRAI.W` 必须使用算术右移。

### 5.4 高位立即数指令

`LU12I.W`：

```text
imm = {inst[24:5], 12'b0}
GR[rd] = imm
```

按 V1.1 约定，当前计划使用 `imm_sel=3'd4`，并可使用 `ALU_PASS_B` 传递立即数。最终须确认 ALU `PASS_B` 语义及写回通路。

### 5.5 访存指令

`LD.W`：

```text
effective_address = GR[rj] + SignExtend(si12, 32)
GR[rd] = dmem_rdata
```

`ST.W`：

```text
effective_address = GR[rj] + SignExtend(si12, 32)
dmem[effective_address] = GR[rd]
```

要求：

- 地址由 ALU 加法计算。
- `LD.W` 使能寄存器写回，写回来源为存储器读数据。
- `ST.W` 禁止寄存器写回，使能存储器写入。
- 当前 `dmem.v` 接口为 `clk`、`we`、`addr`、`wdata`、`rdata`，采用同步写入、组合读取。
- 集成时须确认地址对齐、字节地址到字索引的映射和 FPGA 存储器推断策略。当前 dmem 代码使用 `addr[9:2]` 作为字索引；如要修改，须先共同确认。

## 6. `imm_gen.v` 接口与当前行为

```verilog
module imm_gen (
    input  wire [31:0] inst,
    input  wire [2:0]  imm_sel,
    output reg  [31:0] imm
);
```

选择码：

```verilog
// 3'd0: no immediate
// 3'd1: signed 12-bit, {{20{inst[21]}}, inst[21:10]}
// 3'd2: unsigned 12-bit, {20'b0, inst[21:10]}
// 3'd3: unsigned 5-bit, {27'b0, inst[14:10]}
// 3'd4: upper 20-bit immediate, {inst[24:5], 12'b0}
// 3'd5-7: reserved, output zero in current version
```

当前 Testbench 共有 19 组测试，覆盖无立即数、有符号 12 位、无符号 12 位、无符号 5 位、高 20 位构造和保留选择码。开发记录显示错误计数为 0；提交/报告时应保存本机 Tcl Console 实际输出作为证据。

## 7. 测试计划

### 7.1 立即数生成器边界测试

| 类型 | 输入字段 | 预期结果 |
|---|---|---|
| 有符号 12 位 | `12'h000` | `32'h00000000` |
| 有符号 12 位 | `12'h7FF` | `32'h000007FF` |
| 有符号 12 位 | `12'h800` | `32'hFFFFF800` |
| 有符号 12 位 | `12'hFFF` | `32'hFFFFFFFF` |
| 无符号 12 位 | `12'h800` | `32'h00000800` |
| 无符号 12 位 | `12'hFFF` | `32'h00000FFF` |
| 无符号 5 位 | `5'd31` | `32'h0000001F` |
| 高 20 位构造 | `20'h00001` | `32'h00001000` |
| 高 20 位构造 | `20'h80000` | `32'h80000000` |
| 高 20 位构造 | `20'hFFFFF` | `32'hFFFFF000` |

### 7.2 指令级测试（后续补充）

每条指令至少覆盖普通输入、全零/全一操作数、立即数为零、立即数/移位量边界及目的寄存器为 `r0` 的情况。流水线阶段还应增加数据冒险用例；`LD.W`、`ST.W` 应验证有效地址、读写使能和写回行为。

固定机器码测试值须在官方编码审核完成后补充。

## 8. 待双方确认事项

以下事项未完成共同审核前，不应据此直接编写最终译码器：

- [ ] 对全部 13 条指令逐条复核固定 opcode、匹配掩码及完整 32 位编码；当前第 4.1 节仅整理了 AND、OR、NOR、XOR 四条，仍需队员 A 复核。
- [ ] 队员 A 复核第 4.1 节中 `AND`、`OR`、`NOR`、`XOR` 的 Match/Mask、字段和 `NOR` 操作数顺序。
- [ ] `LD.W`、`ST.W` 的寄存器字段解释和数据通路映射。
- [ ] `decoder.v` 输出端口、位宽、默认行为和非法指令处理。
- [ ] 寄存器堆读写接口及 `r0` 处理方式。
- [ ] `ALU_PASS_B` 与 `LU12I.W` 写回通路的最终连接。
- [ ] dmem 地址单位、字对齐、存储器深度和 FPGA 推断方式。
- [ ] 分支/跳转立即数格式与 `imm_sel` 扩展方案。
- [ ] 本文件与 `docs/interface_spec.md`、`rtl/common/cpu_defs.vh` 的一致性审核。

## 9. Git 协作流程

1. 队员 B 在 `feature/memory` 开发，队员 A 在 `feature/alu` 开发。
2. 模块通过各自 Testbench 后 Commit 并 Push。
3. 涉及公共接口的修改先讨论，再同步更新文档和代码。
4. 稳定模块通过 Pull Request 合并到 `main`。
5. 双方将最新 `main` 同步到自己的开发分支。
6. 集成问题附上复现步骤、仿真日志和相关提交记录。

## 10. 参考资料

1. Loongson, *LoongArch Reference Manual, Volume 1: Basic Architecture*（官方参考手册）：<https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html>
2. Linux Kernel Documentation, *LoongArch Introduction*：<https://docs.kernel.org/arch/loongarch/introduction.html>

> 本文件为项目内部规格草稿，不替代官方 ISA 文档。最终译码器实现前，双方必须逐条复核指令编码与行为。
