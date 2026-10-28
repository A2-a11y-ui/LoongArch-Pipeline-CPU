# V0.7：正式 PC/IF 控制器集成——双方接口交接清单

## A 需提供的交付

1. 正式 PC/IF 控制器 RTL 文件，准确的 `module` 名和完整端口声明（由 A 定义，不预设模块名称）。
2. 同步高有效 rst、Reset PC、Redirect PC 的具体规则；Redirect 是否只发单周期脉冲，以及如何防重复。
3. 接入 Adapter 的信号：`if_req_valid`、`if_req_addr[31:0]`、`if_req_ready`；接收端需要明确 `if_resp_valid`、`if_resp_pc[31:0]`、`if_resp_inst[31:0]`、`if_resp_error`、`if_resp_ready` 的归属。
4. `id_can_advance`、`ifid_flush` 的来源及对应 IF/ID 寄存器 `stall`、`flush` 连接规则。
5. 控制器独立 Testbench 的 `PASS/FAIL` 结果和 Reset/Redirect 的时序波形。

## 必须满足的协议

- 接受请求：`req_fire = if_req_valid && if_req_ready`，只在上升沿计算；被接受之前 `valid` 和 `addr` 稳定（除被 Redirect 取消的旧路径请求）。
- 接受后推进候选 PC；不能在同一个 PC 重复握手；Adapter 允许一次未完成请求。
- 当 EX Redirect 到来，先锁存 target PC，在 Adapter DRAIN 期间保存 target，直到目标请求 `req_fire`。
- `if_resp_ready` 必须仅在本周期 IF/ID 能捕获或者明确处理响应时为 1；Stall/Flush/Redirect 不得误消费旧响应。
- 任何过期 PC 响应不能进入有效 IF/ID；`if_resp_error` 不能变为普通有效指令。
- 若发出下一个请求前发生 Redirect，必须丢弃旧路径候选地址，不能把旧 PC+4 作为新目标。
- 禁止 `ready -> valid -> ready` 组合环。

## 联合测试升级的关键场景

1. 3 条以上顺序取指，PC 每次实际接受后推进 4，全部响应不重不漏。
2. 下游 ID Stall 期间 Adapter 响应稳定，解除后响应只消费一次。
3. Redirect 发生于 Miss 前、中、Cache 完成沿、响应已就绪但反压保持时。
4. Redirect+Stall、Flush+Stall、Reset+Flush+Stall 同周期。
5. 当 A 控制器支持连续 Redirect 时，检查目标 PC 优先级及最终响应来源。
6. 错误地址响应不能成为有效指令；重定向后系统继续前进，不死锁。
7. 不接入真实五级 CPU 之前，不宣称 Forwarding、Load-use、真实 CPU CPI 已完成。

## A/B 分工与冻结门槛

- A：正式 PC/IF 生成和控制、Flush/Stall 生成、IF/ID 原版。
- B：Adapter V0.5.1、两路 I-Cache、V0.6 联合测试和 V0.7 真实控制器联合 Testbench。
- 双方：使用 A 正式 PC/IF 控制器（而不是测试驱动）通过联合测试之后，才确认 V1.0 的 IF 接口冻结。
