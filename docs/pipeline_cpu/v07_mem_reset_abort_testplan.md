# V0.7 MEM Reset-Abort 整机测试计划（独立 Testbench）

**状态：已编写，尚未执行 Vivado 仿真；不得标记 PASS。**

## 用途与分工

PR #31 的基础整机测试已有历史通过证据。本测试覆盖此前未验证的 **CPU 全机 Reset 中止 DMEM 事务及复位后恢复**，不重复队友正在负责的 Branch + MEM Stall / IF 响应反压恢复 / MEM 延迟保持，不修改 `rtl_test_only` 下正式设计文件。

复用已合并的 `tb/pipeline_cpu/programs/v07_mem_basic.mem`（18 条指令），使用新 TB `tb/pipeline_cpu/tb_pipeline_cpu_v07_mem_reset_abort.v`。

## 被测契约（来自当前 RTL）

- `rst`：**同步、高电平有效**，CPU / DMEM 等模块在上升沿清除未完成事务。
- `dmem_latency`：Store **仅在 `resp_valid && resp_ready` 时写入 RAM**，Reset 在响应握手前到达则取消 Store；已提交的 Store **不会被 Reset 回滚**。
- DMEM RAM **复位时不清空**，因此第二轮复位后 `mem[1]` 应保留前面已提交的 `10`。
- 数据通路的 `mem_request_accepted`、流水线 `valid` 状态以及 DMEM 响应有效位需要在复位后清除。
- Reset 后 CPU 从 `PC_BASE=0x1000` 重新执行程序。

## 实测场景及预期（需在 Vivado 中实际运行后填写结果）

| 场景 | 注入条件 | 预期 | 结果 |
|---|---|---|---|
| A：Store 取消 | ST.W `[4]=10` 首次请求**已经握手**、尚未返回响应 | Reset 后 `mem[1]=0`，无该 Store 侧效应 | 待测 |
| B：Load 取消 | 新一轮先确认 Store `[4]=10` 已提交，随后 LD.W `[4]` 请求握手、响应未完成 | Reset 后 `mem[1]=10` 保留，旧 Load 不产生残余 WB | 待测 |
| C：正常恢复 | 第三次从 PC `0x1000` 重新执行程序 | WB=10、Store=3、Branch=1、DMEM Req/Resp=7/7、无多余写回/Store、无异常 | 待测 |

最终 RAM：`mem[1]=10`、`mem[2]=30`、`mem[3]=0`、`mem[4]=32`；`r7=0`。每笔 WB 和 Store 使用和已合并基础 TB 相同的顺序 Scoreboard。

## Vivado 2019.1 执行步骤

1. 从已合并 PR #31 的 `feature/pipeline-cpu-integration` 最新版本创建独立测试分支（可使用团队现有的验证分支，但需避免覆盖队友工作）。
2. **仅新增** `tb/pipeline_cpu/tb_pipeline_cpu_v07_mem_reset_abort.v` 和本测试计划，不改动合并后的 RTL、旧 Testbench、DMEM、程序 ROM。
3. 加入既有整机基础测试所需的全部 Design Sources，并保证 `dmem_latency` **只有一个模块定义**。新增 TB 作为 Simulation Source，设置 Simulation Top=`tb_pipeline_cpu_v07_mem_reset_abort`。
4. 将 Testbench 顶部 `MEM_FILE` 设为本地实际 `v07_mem_basic.mem` 的绝对路径；默认值沿用现有基础 TB 的 Windows 路径。确认 Vivado 可以读到 18 条指令。
5. Run Behavioral Simulation → Tcl Console 执行 `run all`；需要确认输出显示场景 A、B、C 的过程信息和最终 `ALL TESTS PASSED (V0.7 reset-abort CPU integration)`。
6. 另行保存 Tcl Console 完整输出、仿真波形、Vivado 编译/展开/仿真日志；若出现 `FAIL`/`$fatal`，不把本测试标成 PASS，原样提供错误信息。

## 建议波形

`rst`, `dut.u_cpu.mem_pc`, `dut.u_cpu.mem_mem_write`, `dut.u_cpu.mem_request_accepted`, `dmem_req_fire`, `dmem_resp_fire`, `mem_stall`, `mem_store_commit_valid`, `wb_commit_valid`, `dut.u_cpu.u_dmem.state`, `dut.u_cpu.u_dmem.resp_valid`, `dut.u_cpu.u_dmem.mem[1]`。

## 限制

- 本测试使用 DMEM `READ_LATENCY=9`、`WRITE_LATENCY=11`，其余运行环境与基本整机测试一致；在同一份 ROM 上执行多次复位。
- 该 TB 不覆盖外部 IF 背压恢复、Branch/MEM Stall 可控冲突、错误地址异常入口、板级硬件时序；不能把这条测试的 PASS 解释为 V0.7 所有验证已完成。
- 需要在 Vivado 2019.1 中实际编译运行后，才能填写执行日期、PASS/FAIL、日志及截图证据。
