# V0.4 Branch Redirect / Flush 第一阶段独立验证计划

> 版本日期：2026-10-29。目标 Vivado 2019.1 / Verilog-2001。
>
> 这是一份 **V0.4 整机正式顶层发布之前** 的测试准备资料。
> 所有 DUT 均来自团队集成分支已存在的正式模块，**不新增或修改正式 RTL**。

## 范围与验收目标

| 层次 | Testbench | 现有正式 DUT | 预期目标 |
|---|---|---|---|
| 1：指令译码至分支目标 | `tb_branch_decode_redirect_v04.v` | `decoder.v`、`imm_gen.v`、`branch_unit.v` | 23 cases、276 个输出检查、errors=0 |
| 2：重定向与流水线清空控制 | `tb_branch_flush_control_v04.v` | `pc_if_controller.v`、`pipeline_control_unit.v`、`if_id_reg.v`、`id_ex_reg.v`、`ex_mem_reg.v` | 至少 65 项检查、errors=0 |

此包不实例化尚未发布的 `pipeline_cpu_core_v04.v`，不能用于宣称“Branch + Load/Store 整机回归通过”。

### 第一套覆盖

- BEQ taken / not-taken、BNE taken / not-taken；rj / rd 寄存器读地址与比较顺序。
- B、BL、JIRL 前向/后向、零偏移及 32 位地址回绕。
- 有符号 B16 和分段 B26 offset 解码、字节偏移左移 2 位。
- BL 必须向 `r1` 写入链接地址；JIRL 的目的寄存器来自 `rd`。
- JIRL 的跳转目标使用 `rs1_data + offset`，而非 `PC + offset`。
- 非法编码不能发出 Redirect；普通 ADDI 指令不能误认为分支。
- 注意：本层检查 BL/JIRL **译码写使能 / 目的寄存器 / wb_sel**，尚未检验整机真实 PC+4 写回。

### 第二套覆盖

- 复位 `RESET_PC=0x1000`，禁止发取指请求，清除有效位。
- 正常 IF request accepted 时 PC+4；`if_req_ready=0` 时请求 PC 保持。
- Redirect 优先于普通取指，装载 `redirect_pc`；抑制旧 PC 请求。
- EX 阶段 Redirect 必须 Flush IF/ID、ID/EX；较老的 EX 进入 EX/MEM，不应该被错误 Flush。
- Load-use Hold IF/ID、Bubble ID/EX、保持未接受的 PC，请求恢复后继续前进。
- Redirect 优先于 Load-use，Reset 优先于 Redirect。
- 这里 Load-use 与 Redirect 是 **外部合成控制刺激**，不是完整分支/访存流水线行为。

## 放到 Git 仓库的目录

```text
tb/pipeline_cpu/
  tb_branch_decode_redirect_v04.v
  tb_branch_flush_control_v04.v

docs/pipeline_cpu/
  branch_v04_preintegration_testplan.md
```

## GitHub Desktop

1. `Fetch origin`，切换 `feature/pipeline-cpu-integration`，必要时 `Pull origin`。
2. 从最新 integration 新建分支 `feature/pipeline-branch-verification`。
3. 将本包的 `tb/` 和 `docs/` 合并到项目根目录，先不要修改 V0.3 或 I-Cache 正式代码。

## Vivado 测试 1：Decode + Imm + Branch

**Design Sources**：

- `rtl/common/decoder.v`
- `rtl/memory_cache/imm_gen.v`
- `rtl/alu_branch/branch_unit.v`
- `rtl/common/cpu_defs.vh`（用于 Decoder 的 include；保留工程已配置的 include 搜索路径）

**Simulation Sources**：`tb/pipeline_cpu/tb_branch_decode_redirect_v04.v`

```tcl
set_property top tb_branch_decode_redirect_v04 [get_filesets sim_1]
report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
```

然后运行 **Run Behavioral Simulation**，正常测试自动调用 `$finish`。不要在已完成之后重复 `run all`。

预期末尾：

```text
V0.4 BRANCH DECODE + IMM + DECISION REGRESSION
cases=23 checks=276 errors=0
ALL TESTS PASSED
```

## Vivado 测试 2：PCU + PC/IF + IF/ID + ID/EX + EX/MEM

**Design Sources**：

- `rtl/common/pc_if_controller.v`
- `rtl/common/pipeline_control_unit.v`
- `rtl/common/if_id_reg.v`
- `rtl/common/id_ex_reg.v`
- `rtl/common/ex_mem_reg.v`

**Simulation Sources**：`tb/pipeline_cpu/tb_branch_flush_control_v04.v`

```tcl
set_property top tb_branch_flush_control_v04 [get_filesets sim_1]
report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
```

预期末尾：

```text
V0.4 BRANCH REDIRECT + PIPELINE FLUSH PRE-INTEGRATION
checks=65 errors=0
ALL TESTS PASSED
```

如果结果不符，请提供第一次 `FAIL` 的 Tcl Console 信息和仿真日志。暂时不更改官方 PCU/PC_IF_Controller。

## 保存证据与提交

仅在 **真实 Vivado 通过之后** 保存：

```text
docs/pipeline_cpu/evidence/v04_branch_decode_pass.png
docs/pipeline_cpu/evidence/v04_branch_decode_compile_order.txt
docs/pipeline_cpu/evidence/v04_branch_flush_pass.png
docs/pipeline_cpu/evidence/v04_branch_flush_compile_order.txt
```

全部通过后使用 `test(cpu): prepare V0.4 branch redirect and flush verification` 作为提交说明，Commit/Push 当前验证分支。是否立即创建独立 PR 与 A 协调；不必等其整机 V0.4 代码，但不要把此包称为 V0.4 整机完成。

## A 的 V0.4 整机到来后：下一轮不可缺少的验证

1. 分支真正从 EX 发起 Redirect，检查更年轻的 IF、ID 指令被 Kill。
2. **错误路径的 ST.W 绝不写入 DMEM**；错误路径 WB 绝不提交；Older EX/MEM 的合法副作用仍保留。
3. BEQ/BNE taken/not-taken，B、BL、JIRL 的目标 PC 正确；BL/JIRL 的 PC+4 写回正确。
4. Branch 与 Forwarding 混合，Load-use 与 Branch 同时出现时优先级正确。
5. IF ready/valid、重定向和 Cache Adapter 的未完成事务：取消过期响应、避免丢指令/重复发出。
6. 特别注意：PCU 的 `hold_fetch_issue_req` 仅是 **advisory**；不能直接取消已保持的 Adapter valid。需要按照正式握手协议驱动。
7. Store Commit / Register WB 按 PC/rd/addr/data 逐笔校验，统计 Redirect、Flush 和有效/无效提交。

正式 V0.4 接口实际发布后，再基于新接口编写独立 ROM+scoreboard Testbench。

## 静态校验状态

23 个编码测试向量已通过独立 Python ISA 参考模型的 276 个预期字段核对。未在本环境执行 Icarus Verilog 或 Vivado；因此 `ALL TESTS PASSED` 仅是预期字符串，**不是仿真成绩**。
