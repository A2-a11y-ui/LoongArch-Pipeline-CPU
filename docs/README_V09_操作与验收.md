# V0.9 IF/ID → ID/EX 正式寄存器联合验证（Vivado 2019.1）

## 基线 / 范围
基于 main 中已合并的 PR #17 正式 `rtl/common/id_ex_reg.v` 和 PR #18 V0.8 接口。
**本包只新增测试连接层及 Testbench，不修改正式 RTL。** 当前采用确定性模拟译码字段（synthetic decode），不代表真实 LoongArch 译码或完整五级流水线。

## 新文件
- `rtl_test_only/ifetch_idex_integration_v09.v`：连接正式 V0.8、正式 ID/EX。使用 `id_pc + 4`；其余 ID 控制字段由模拟译码映射得到，专用于验证存储传递。
- `tb/tb_ifetch_idex_integration_v09.v`：保留 V0.8 的 18 个场景并增加 6 个 ID/EX 场景。每个时钟沿检查 223-bit、19 字段记录和 PC+4 一致性。

## 关键边界
1. `hold_fetch_issue_req` 仍仅建议，不接入 PC 请求 valid；协议不能随意撤销。
2. `idex_flush` 在 Load-use 时产生 Bubble，只有模拟的 ID/EX，没有 EX/MEM、真实 load 指令执行；正式 hazard 检测仍由测试输入表示。
3. `id_can_advance_external=0` 时两个前级保持，ID/EX 使用单独 stall；Reset/Flush 优先于 Stall。
4. 本包没有实现正式译码、寄存器堆、ALU、数据存储器、BL/JIRL 的真实执行，只验证 19 字段/PC+4 在流水线时序中正确传递。

## 安装
1. GitHub Desktop 从最新 main 建分支 `feature/if-idex-integration-v09`。
2. 复制两个新文件到仓库同名目录，**不覆盖 V0.7/V0.8**。
3. Vivado Add Sources: `rtl_test_only/ifetch_idex_integration_v09.v` 到 Design Sources，`tb/tb_ifetch_idex_integration_v09.v` 到 Simulation Sources。
4. 将 sim_1 Top 设为 `tb_ifetch_idex_integration_v09`；确认原版九个文件 + 正式 `id_ex_reg.v` + 新增两个 V0.9 文件全部参与编译（共 12 个）。
5. `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation` 检查 Missing instances 为空。
6. Close Simulation 后重新 Run Behavioral Simulation、`run all`。出现错误请提供首次 FAIL、compile/elaborate/simulate.log。
7. 保留真实 XSIM 结果截图和编译顺序；**此代码尚未在 Vivado 2019.1 实际运行，不能宣称通过**。

## 新增场景 19—24
19. 取指经真实 ID/EX 捕获，PC+4/指令值匹配。
20. Load-use 时 IF/ID 保持、真实 ID/EX 清空，并在解除后恢复。
21. Redirect 优先于 Hazard，清空两个前级，随后目标 PC/PC+4 正确。
22. 外部 backpressure 时 ID/EX 全字段保持。
23. Reset 同时遇到 Redirect/Hazard/Stall，两个前级清空，重新从 RESET_PC 开始。
24. 非法取指的错误响应不可成为 EX 有效指令。

## 说明
V0.8 原 18 场景全部保留；原 Testbench 中 `dut.u_ifetch` 层级引用在 V0.9 中变为 `dut.u_v08.u_ifetch`。检查项数随仿真时钟数变化，以实际运行输出为准。
