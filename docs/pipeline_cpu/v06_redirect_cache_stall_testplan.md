# V0.6 Redirect × Outstanding I-Cache × Downstream Stall 独立测试计划

## 范围与重要边界

- **不修改**稳定的 `pipeline_cpu_core_v05.v`、`pipeline_cpu_core_v04.v`、`icache_if_adapter.v`、`icache_2way_latency.v`、`imem_latency.v`、`pc_if_controller.v` 及其它正式 RTL。
- **场景 A 是真实指令执行**：`BEQ` 位于 PC `0x100C`，16-byte Cache Line 最后一个 word；顺序错误路径 `0x1010` 是新的 Cache Line，造成 outstanding miss，与 EX Redirect 重叠。期望 `ST_WAIT -> ST_DRAIN -> ST_IDLE`。旧响应不能进入 CPU。目标 PC 是 `0x1020`。
- **场景 B 是 Testbench 定向协议注入**：在 `0x1004` 旧响应处于 Adapter `ST_RESP`、`if_delivery_allow=0`，并保持至少两周期后，使用 `force/release dut.branch_redirect` 和 `dut.branch_redirect_pc` 注入一个 Redirect 到 `0x1020`。检查旧响应被屏蔽和 Flush。**这不是自然产生的 Branch，也不是自然 Load-use Hazard，不能声称两场景均由真实分支程序自然触发。**
- 一份 ROM，包含 12 个 32-bit word，CPU 虚拟 PC `0x1000` 起，IMEM 物理 PC 减去 `0x1000`。
- 测试中 `load_use_stall` 的出现次数不作为本阶段目标。
- 单 outstanding 接口，不要求一周期接受一条指令。

## 场景 A：真实分支与未完成 Miss

1. `0x1000, 0x1004, 0x1008` 分别执行 `ADDI.W r2=5`、`r3=5`、`r4=2`。
2. `0x100C` 执行 `BEQ r2,r3,+20`，真实 EX 判定 Taken。
3. CPU 试图请求顺序 PC `0x1010`；其 Cache Line 此前未被填充，形成 Miss。
4. Redirect 当周期要求：适配器正处 `ST_WAIT`、`pending_pc=0x10`、`cache_ready=0`，`if_req_fire=0`、`if_resp_fire=0`。
5. 后续要求观测 `ST_DRAIN`，旧请求完成时旧响应不对 CPU 有效；再请求 `0x1020`，目标指令恰好一次。
6. Wrong path 的 `0x1010` Store 和 `0x1014` WB 必须为 0；`0x1018` Store、`0x101C` WB 同样为 0。
7. 期望 WB 顺序为：
   - `(0x1000,r2,5)`、`(0x1004,r3,5)`、`(0x1008,r4,2)`、`(0x1020,r5,9)`、`(0x1028,r6,10)`。
8. 期望 Store 顺序为：`(PC=0x1024,addr=0,data=9)`、`(PC=0x102C,addr=4,data=10)`。

## 场景 B：待处理响应与下游反压、定向 Redirect

1. 再次 Reset，CPU 接收 `0x1000`。
2. 下游设置 `if_delivery_allow=0`；等待 `0x1004` 响应进入 `ST_RESP`，保持至少两个完整周期。
3. 暂停期间检查 `if_resp_hold`、PC/Instruction 的跨周期稳定、`if_resp_fire=0`。
4. 定向注入 Redirect 到 `0x1020`；检查当周期 `if_req_fire=0`、`if_resp_fire=0`、Adapter 不暴露有效旧响应。
5. 释放 `force/release` 后恢复 `if_delivery_allow=1`，第一条新请求必须是目标 PC `0x1020`，且仅请求/交付一次。
6. `0x1004..0x101C` 无 WB/Store 作用。
7. 期望 WB 为 `(0x1000,r2,5)`、`(0x1020,r5,9)`、`(0x1028,r6,10)`；期望 Store 与 A 相同。

## Scoreboard/断言

- 取指请求只允许一个 outstanding；Redirect 重置 logical epoch；完成响应的 PC 必须匹配当前 outstanding。
- IF 交付的数据必须与静态 ROM 机器码一致。
- Redirect 同周期禁止请求、响应的成功握手。
- target request 和 target delivery 各 **恰好一次**，不允许多余请求或交付。
- 错误路径的 WB 和 Store 事件不得出现，正确路径 WB/Store 用预置数组逐笔对比。
- 最终 DMEM word0=9、word1=10。
- 超时检测不允许死锁；完成后额外运行若干周期检测延迟的重复提交。
- 独立计数：`redirect_while_cache_busy`、`redirect_while_response_pending`、`stale_response_dropped`、`stale_pending_flushed`、`target_fetch_count`、`wrong_path_wb_count`、`wrong_path_store_count`。

## 运行与归档

1. 在 Vivado 2019.1 `Add Sources > Add or create simulation sources` 中新增 `tb_pipeline_cpu_v06_redirect_cache_stall.v`。
2. 原有 V0.5 正式设计源码保持在 `Design Sources`，不要重复加入同名模块；本次不增加任何新的正式 Design RTL。
3. ROM 文件需放在 `tb/pipeline_cpu/programs/v06_redirect_cache_stall.mem`；Testbench 默认使用项目已约定的 Windows 绝对路径，其他电脑可用 `+MEM_FILE=...` 覆盖。
4. 设置仿真顶层 `tb_pipeline_cpu_v06_redirect_cache_stall`，`Run Behavioral Simulation`，然后 Tcl Console 中执行 `run all`。
5. **实际执行 Vivado 2019.1 后**确认两阶段 `check_phase` 通过，`errors=0` 且显示 `ALL TESTS PASSED`；再保存 `docs/pipeline_cpu/evidence/v06_redirect_cache_stall_pass.png` 和完整 Tcl Console 日志。
6. 执行 `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`，检查 `Missing instances` 为空。
7. 未通过前，不应把该包描述为已经过 RTL/Vivado 验证，也不要 Merge。

## 如果场景 A 失败如何排错

若报 `phase A did not overlap outstanding next-line miss`，请保存波形：`branch_redirect`、`branch_redirect_pc`、`dut.u_adapter.state`、`dut.u_adapter.pending_pc`、`dut.u_adapter.cache_ready`、`dut.u_icache`（实际为 `dut.u_adapter.u_icache`）的状态与 Cache Miss 计数。若某个架构细节使重叠无法在此程序中自然出现，**应先报告并调整测试构造，不要修改稳定 RTL 来迎合 Testbench**。

## 验证声明

此测试源码由 ChatGPT 基于用户提供的正式 V0.5 / Cache / CPU RTL 接口制作，并进行了静态核对与机器码指令映射校验；当前环境无法运行 Vivado/XSim，因此 **尚无实际仿真 PASS 证据**，必须以用户的 Vivado 2019.1 运行结果为准。
