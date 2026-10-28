# Stage 3：自动 PC + IMEM + Decoder/Datapath 集成验证

项目：LoongArch-Pipeline-CPU，Vivado 2019.1，Verilog-2001。

## 已验证的起点

用户已经在 Vivado 完成 `tb_fetch_datapath_stage2`：85 项检查、0 错误，仿真结束于 216 ns。这一轮 PC 是由 Testbench 提供的。

## 本轮目标

- 使用队员 A 已约定的 `pc_reg(clk,rst,pc_en,next_pc,pc)` 模块，实现自动 PC+4；
- PC 不允许更新时，不再重复执行/写入上一条指令；
- `redirect` 时插入一次不执行当前指令的重定向周期（bubble），下周期执行目标地址的指令；
- 验证复位优先、字节 PC 步进、连续依赖指令、`LD.W/ST.W`、无效指令和越界地址保护；
- 保持测试结构为单周期教学集成原型；不声明已经实现 LoongArch 分支指令、流水线/冒险前递或 I-Cache。

## 文件

| 文件 | 放置位置 | Vivado 来源 |
|---|---|---|
| `pc_fetch_stage3.v` | `rtl/common/` | Design Sources |
| `tb_pc_fetch_stage3.v` | `tb/` | Simulation Sources |
| `pc_reg_reference.v` | `sim_reference/` | 仅在正式 `pc_reg.v` 未完成时，加入 Simulation Sources |

`pc_reg_reference.v` 内部模块名为 `pc_reg`，不能与队员 A 的正式 `pc_reg.v` 同时加入工程。正式版进入 main 后，应**移除参考模型**并重新运行完全相同的测试。

## 依赖的已有模块

- `rtl/common/fetch_datapath_stage2.v`
- `rtl/common/datapath_stage1.v`
- `rtl/common/decoder.v`
- `rtl/common/cpu_defs.vh`
- `rtl/memory_cache/imem.v`
- `rtl/memory_cache/imm_gen.v`
- `rtl/memory_cache/dmem.v`
- `rtl/alu_branch/alu.v`
- 队员 A 正式 `regfile.v`
- 队员 A 正式 `pc_reg.v`（若未到位，用测试专用参考实现）

## 当前模块接口

```verilog
module pc_fetch_stage3 (
    input  wire        clk,
    input  wire        rst,
    input  wire        step_en,
    input  wire        redirect,
    input  wire [31:0] redirect_pc,
    output wire [31:0] pc,
    output wire [31:0] inst,
    output wire        fetch_addr_valid,
    output wire        instr_valid,
    output wire        dbg_reg_we,
    output wire        dbg_mem_we,
    output wire [31:0] dbg_wb_data,
    output wire [31:0] dbg_alu_result
);
```

## 时序规则

| `rst` | `step_en` | `redirect` | 本周期状态与下周期 PC |
|---:|---:|---:|---|
| 1 | X | X | 上升沿 PC=0，regfile 同步清零 |
| 0 | 0 | X | PC 保持，禁用寄存器/存储器写使能 |
| 0 | 1 | 0 | 在上升沿执行当前 PC 指令，并更新 PC+4 |
| 0 | 1 | 1 | 当前指令不提交写回；在上升沿更新至 `redirect_pc` |

重定向仅用于测试 PC 目标选择和控制连线，不代表已实现 BEQ/BNE/JIRL 等 LoongArch 分支/跳转指令。后续流水线的 flush 与 PC 选择必须另行设计。

## Vivado 操作

1. 在 `feature/memory` 中保存已完成的第 2 阶段代码；**不要覆盖**队员 A 的 `pc_reg.v`。
2. 先把前两个文件复制到上述目录。检查项目 Sources 中已有的依赖模块。
3. 仅当正式 `pc_reg.v` 未进入本地工作分支时，添加 `sim_reference/pc_reg_reference.v` 到 **Simulation Sources**。若正式版已存在，跳过参考文件。
4. `Add Sources -> Add or Create Design Sources` 添加 `pc_fetch_stage3.v`。
5. `Add Sources -> Add or Create Simulation Sources` 添加 `tb_pc_fetch_stage3.v`。
6. 将 `tb_pc_fetch_stage3` 设置为 **Set as Top**。
7. `Run Simulation -> Run Behavioral Simulation`。
8. Tcl Console 需出现 `Total errors = 0` 与 `ALL TESTS PASSED`。本包没有在用户 Vivado 2019.1 实机执行过，必须以实际结果为准。
9. 截图保留 PC 的变化、`step_en` 的暂停、`redirect` 的跳转、`dbg_reg_we`、`dbg_mem_we`、最终统计。

### 常见错误

- 找不到 `pc_reg`：确认正式模块或参考模块之一存在；仿真模型应加入 **Simulation Sources**。
- `module pc_reg already defined`：正式版与参考版重复，移除参考版。
- `pc_fetch_stage3` 找不到：确认其在 Design Sources。
- `cpu_defs.vh` 找不到：沿用你此前已经解决的 Vivado include 配置。
- 运行时 `FAIL`：复制 Tcl Console 第一条失败项目，不要盲目改队员 A 的模块。

## 协作与提交建议

先让队员 A 审核 `pc_fetch_stage3.v` 对 `pc_reg` 的连接方式。如果采用参考 `pc_reg`，不要把它提交到公共 RTL 路径。后续两人将整合指令译码（至少 25 条）、分支控制、五级流水线、冒险检测和 I-Cache，并补充性能对比。
