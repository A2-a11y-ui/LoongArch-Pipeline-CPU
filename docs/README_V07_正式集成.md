# V0.7 正式 PC/IF + I-Cache 联合集成：Vivado 2019.1

## 本包新增两个文件
- `rtl_test_only/ifetch_subsystem_v07.v`：用 A 的正式 `pc_if_controller` 替换 V0.6 的临时 `if_pc_driver_v06`；其他连线保持不变。
- `tb/tb_ifetch_subsystem_v07.v`：以已通过的 V0.7 Precheck 12 类用例为基础，转测正式 V0.7 连接顶层。

## 必需依赖（从已合并仓库使用，包内不重复提供）
- A 正式模块 `rtl/common/pc_if_controller.v`（请先审核 PR #14，合并并同步 main；如 PR 尚未合并，可在独立测试工作区引用 A 的正式源码，不要覆盖 main）。
- A 正式 `rtl/common/if_id_reg.v`。
- B 的 `rtl/memory_cache/icache_if_adapter.v`（V0.5.1）。
- B 的 `icache_2way_latency.v` 和 `imem_latency.v`。

## 添加到 Vivado 的建议
1. 将本包两个文件放进仓库对应目录（当前分支 `feature/if-fetch-official-integration`）。
2. 在 Vivado `Add Sources -> Add or Create Simulation Sources` 新增两个文件，或将连接模块加入 Design Sources 并在仿真集使用。
3. 确保正式 `pc_if_controller.v` 已作为 Design Source 或 Simulation Source 可用于 sim_1；`if_id_reg.v` 使用 A 的正式版，不可加入 `reference_optional` 的同名替身。
4. 右键 `tb_ifetch_subsystem_v07` -> Set as Top，Run Behavioral Simulation，然后在 Tcl Console 输入 `run all`。
5. 检查完整日志的 FAIL、`Total errors = 0`、`ALL TESTS PASSED`；禁止在未实测前宣称通过。

## 测试边界
CASE1-12：顺序取指/跨行、Miss、IF/ID 反压、普通 Redirect、Miss 中 Redirect、完成沿 Redirect、Flush/Stall/Reset 优先、错误响应、局部 IF/ID flush 不取消 Cache 事务等。
这仍是取指子系统测试，不包括 Load-use Unit/Forwarding 的整机集成；正式 PC 模块尚无 `hold_if_req` 端口，后续 A 的流水线控制需定义阻止新请求和保持未握手请求的明确机制。

## 审核注意
- `if_pc_driver_v06.v` 和 V0.6 已通过 Testbench 保留作回归对照，不要删除。
- 切勿添加两份同名模块定义；本包未打包 Cache 和 IF/ID 的参考版。
- PR #14 的 GitHub 实际变更未能通过当前连接直接读取，必须先核对 PR Files changed 与 A 给出的源码一致。
- 若 Vivado 出现 ERROR，提供 compile/elaborate/simulate.log；若 FAIL，提供具体 FAIL 和 Total errors。
