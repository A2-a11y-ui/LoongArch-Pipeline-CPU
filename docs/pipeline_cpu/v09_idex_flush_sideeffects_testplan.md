# V0.9 独立 ID/EX Flush 副作用专项验证（Vivado 实测通过）

## 1. 目的和版本

本测试独立于 PR #42 的 40 字 Stage3 整机回归，专门针对 PR #41 对 `rtl/common/id_ex_reg.v` 的时序优化。

本次专项测试**不修改任何生产 RTL**。由以下两个**真实模块**参与仿真：

- PR #41 的优化版 `rtl/common/id_ex_reg.v`：从队友提供的《提交给A的文件.zip》提取，SHA-256（文件字节）为 `7643259cf1007779033a4bc6e0da2f4a72d0a3e9bba2088803195dcd9eaec3fa`。
- 项目现有稳定版 `rtl/common/ex_mem_reg.v`：本测试使用该模块将 ID/EX 的无效控制传给下一流水级。应从本地项目选择此文件，而非额外添加多个重复定义。

Testbench：`tb/pipeline_cpu/tb_v09_idex_flush_sideeffects.v`。

**实测状态：已在用户本机 Vivado 2019.1 复现通过（8 Cases、95 Checks、0 Errors，346 ns）；记录仅针对下述 ID/EX + EX/MEM 定向验证范围。**

## 2. 测试机制

- 逐时钟沿检查 `ex_valid` 和 **全部 222 bit** ID/EX Payload，而不只抽查 PC、操作数或写使能。
- 故意在 Flush/invalid 时注入 `id_reg_write=1`、`id_mem_write=1` 以及复合非法控制位，检查 Flush 后虽有残留原始控制字段，但 `ex_valid` 必须为零。
- 再推进一个时钟，检查真实 `ex_mem_reg` 收到 `mem_valid=0`，即使原始 `mem_reg_write`/`mem_mem_write` 保留为 1，也不得满足有效提交资格。
- 检查 `Reset > Flush > Stall > Capture` 对 `ex_valid` 的优先级，以及优化版 Payload 单独采用 `Reset > Stall > Capture` 的正确行为：无 Stall 的 Flush 可以覆盖 Payload；Flush+Stall 必须保持 Payload。
- 用 Stage3 程序的 `0x001C0885`（MUL.W，PC `0x1010`）构造 ID/EX 中的 MDU 指令，在连续八拍模拟的上游停顿和下游阻塞下比较所有 222 bit 是否保持。

### 测试案例（共 8 组，实测 95 项检查）

| # | 场景 | 重点预期 |
|---|---|---|
| 1 | Flush + `reg_write=1` | `ex_valid=0`；下一拍 `mem_valid=0` |
| 2 | Flush + `mem_write=1` | 无效 EX/MEM 不能满足 Store 资格 |
| 3 | Flush + `reg_write=1` + `mem_write=1` | 两种写控制位均可保留，但均不得成为有效操作 |
| 4 | Flush + 所有读写控制位为 1 | 无效槽位不产生有效副作用资格 |
| 5 | Flush + Stall 同时 | Flush 清 valid，Stall 保持完整 Payload；旧的更老指令仍允许先前进 |
| 6 | Reset + Flush + Stall 同时 | Reset 清 valid 与全部 Payload；释放后无幽灵指令 |
| 7 | MDU Payload 连续 8 拍停顿 | PC、指令字、操作数、rd、写控制等全部保持；解除 Stall 后有效位按输入更新 |
| 8 | `id_valid=0` 但写使能为 1 | 不得成为有效 EX 或 MEM 提交资格 |

## 3. 测试覆盖边界（重要）

`ex_wb_eligible`、`ex_store_eligible`、`mem_wb_eligible` 和 `mem_store_eligible` 是按 `valid` 门控的**副作用资格观测**。这套 Testbench 没有实例化完整 RegFile、DMEM 或 MDU，因此**不能**把该观测等同于全 CPU 已经实际验证了无 WB/Store 提交，也不能把模拟的连续 Stall 声称为 MDU 和 MEM 的真实握手并发。

补充的整机安全证据来自 PR #42：40 字 Stage3 程序在 FPGA CPU 包装模块行为仿真下获得 WB 29/29、Store 3/3、MDU 14/14、DMEM 6/6、Errors 0、PROGRAM_DONE=1。已通过 Vivado 编译路径核对及三个关键文件与 PR #41 Commit `6cf92ee406c42cdc0853da743b690c6c69304fef` 的逐字节对照，并使用优化版重新执行 `restart` / `run all`，仍然通过。上述程序不一定强制触发全部控制冲突组合。

其他独立验证已有如下结果：Adapter `ST_WAIT` / `ST_RESP` / `ST_DRAIN` Redirect 专项 8 Cases、341 Checks、Errors 0；EGO1 FPGA 顶层 Reset/Replay 行为仿真 2 Runs、75 Checks、Errors 0。**这些属于各自独立 Testbench 的证据，不能算作本 ID/EX 专项 Testbench 的覆盖。** 对真实 MDU Done 与 MEM Stall 恰好并发的特定冲突时序，以及 EGO1 实际板卡运行，仍应避免超出已测范围的声明。

## 4. Vivado 2019.1 GUI 运行说明

1. 本测试位于独立分支 `test/pipeline-v09-idex-sideeffects`，与 PR #42 分开维护；PR 目标建议设为 `feature/pipeline-v09-fpga-integration`，因为专项验证对应 PR #41 的优化版 RTL。不要把 PR #42 的 40 字程序与 Testbench 重复提交。
2. 将 `tb/pipeline_cpu/tb_v09_idex_flush_sideeffects.v`、本测试计划和对应通过截图保留在独立验证分支；不要修改 `rtl/common/id_ex_reg.v`。Adapter 和 Reset 另有独立 Testbench 与证据。
3. 在 Vivado `Add Sources` → `Add or create design sources` 中确认编译到的 `id_ex_reg.v` 是 B 的 **PR #41 优化版本**。若当前工程指向旧版，可从 B 的压缩包解压优化版到仓库之外的独立审核文件夹，并从 Vivado 移除旧引用（仅 `Remove from Project`、**不删除磁盘文件**），再添加优化版。项目内只允许一个 `module id_ex_reg` 定义。
4. Design Sources 还需要稳定版 `ex_mem_reg.v`，同样只保留一个定义；不需要为这轮单模块测试添加整个 CPU/Cache/FPGA 顶层，也不需要 XDC。
5. `Add Sources` → `Add or create simulation sources` → 添加 `tb_v09_idex_flush_sideeffects.v`。
6. 在 `Simulation Sources` 中右键 `tb_v09_idex_flush_sideeffects` → `Set as Top`。点击 `Run Behavioral Simulation`；在 Tcl Console 输入 `run all`。
7. **已在 Vivado 2019.1 实测通过**：`V09 IDEX SIDE EFFECTS RESULT CASES=8 CHECKS=95 ERRORS=0` 和 `ALL TESTS PASSED (ID/EX + EX/MEM directed verification only)`；仿真结束于 346 ns。
8. 保存 Tcl Console 截图和完整日志，并记录使用的 `id_ex_reg.v` 的 SHA-256。若 FAIL，不改正式 RTL、不降低断言，把完整报错和代码版本留给双方复核。

## 5. 后续证据与提交

- 实测截图已保存为 `docs/pipeline_cpu/evidence/v09_idex_flush_sideeffects_pass.png`，工具为 Vivado 2019.1，仿真结束于 346 ns。
- 专项 PR 的目标分支建议为 `feature/pipeline-v09-fpga-integration`（PR #41 的源分支）；仅提交独立 Testbench、测试计划和实测证据，不包含 B 的正式 RTL，也不要重复提交 PR #42 的 Stage3 文件。创建 PR 后以 Files changed 为准再次检查。
- 在最终 PR #41 审核意见中区分：ID/EX+EX/MEM 定向验证、Adapter Redirect 定向验证、PR #42 FPGA Wrapper Stage3 整机回归、FPGA 顶层 Reset/Replay 行为仿真，以及仍未完成的 EGO1 实机下载与板级验收。


## Vivado 2019.1 实测结果

测试对象：PR #41 优化版 id_ex_reg.v + ex_mem_reg.v

- Cases：8
- Checks：95
- Errors：0
- Simulation Finish：346 ns
- Result：ALL TESTS PASSED

本次验证覆盖 ID/EX Flush 副作用、Flush 与 Stall
并发、Reset 优先级、Payload 保持和无效指令控制。

本次为 ID/EX + EX/MEM 定向行为验证，
不等于整个 FPGA CPU 的所有执行场景均已通过。

证据：
docs/pipeline_cpu/evidence/v09_idex_flush_sideeffects_pass.png