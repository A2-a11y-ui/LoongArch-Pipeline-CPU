# V0.6 五级流水线取指子系统联合仿真 — 操作说明

## 目标 / 边界

本包联合验证 **IF PC 请求参考模型 + 队员 A 的 IF/ID Register + 队员 B 的 Adapter V0.5.1 + 2-Way LRU I-Cache + 固定 3 周期后备存储器**。
不改原来的 `cpu_top.v`，不修改 `icache_if_adapter.v` / `icache_2way_latency.v`；使用的 IF 控制器 `if_pc_driver_v06.v` **仅为临时测试参考**，不是队员 A 将提交的流水线正式 PC/IF 控制模块。

## 必须加入 Vivado 2019.1 的文件

在 **Design Sources** 确认已有：
- `rtl/common/if_id_reg.v`（队员 A 的原版；若 PR #7 未合并可从队员 A 获取）；
- `rtl/memory_cache/icache_if_adapter.v`（V0.5.1）；
- `rtl/memory_cache/icache_2way_latency.v`（V0.3）；
- `rtl/memory_cache/imem_latency.v`（V0.2）。

**Simulation Sources** 新增以下三个文件：
- `rtl_test_only/if_pc_driver_v06.v`；
- `rtl_test_only/ifetch_subsystem_v06.v`；
- `tb/tb_ifetch_subsystem_v06.v`。

如果缺 `if_id_reg.v`，ZIP 中 `reference_optional/if_id_reg_A_reference.v` 是从聊天里队员 A 所给代码整理的对照文件，**只在没有原始 RTL 时临时添加，禁止同时添加两份同名 `module if_id_reg`**。正式联调应优先使用 A 的真实 GitHub 文件。

设置 Simulation Top 为 `tb_ifetch_subsystem_v06`，选择 **Run Behavioral Simulation** 后执行：

```tcl
run all
```

如果出现 elaborate 错误，查看 `elaborate.log` 中第一条 `[VRFC]`，优先检查模块文件和端口名。切勿将测试专用 IF 控制器设置为硬件综合顶层。

## 联合用例

1. 顺序取指三条以上：首次 Miss 后同一行中命中，PC 递增4；
2. Cache Miss + IF/ID Stall：Adapter 有效响应保持，恢复后仅消费一次；
3. Miss 时 Redirect：旧请求 DRAIN，不污染 IF/ID，新目标最终返回；
4. 响应已就绪且下游 Stall 时 Redirect：旧结果取消；
5. Cache 即将 READY 同周期 Redirect：旧响应禁止发布；
6. IF/ID Flush 与 Stall 同时：Flush 优先，清零 valid；
7. Reset + Flush + Stall：Reset 优先；
8. 非法地址 `0x400`：错误响应不得成为有效指令；
9. Stall + Flush + Redirect：正确目标不丢失。

测试平台每个上升沿会检查 IF/ID 的实际寄存器值，并追踪请求接受/响应消费的顺序、指令字与 ROM 的关系，发现错误打印 `FAIL`。只有在本人 Vivado 中跑出 `Total errors = 0` 才能标记 V0.6 联合仿真通过。

## 注意事项

- 后备存储器 `imem_latency` 仿真 ROM 值是 `32'hA5000000 | (PC>>2)`，不是正式 LoongArch 可执行程序。
- 本包不检测 EX/MEM、Load-use Forwarding 或真正 CPU CPI，只检查取指接口；不保证最终 IPC=1。
- Adapter 的 `busy` **不直接**接 IF/ID.stall。`if_resp_ready = !rst && !redirect && !ifid_flush && id_can_advance`。
- 在单请求设计中顺序 PC 在 `req_fire` 时递增，Redirect 新目标优先锁存；旧 Miss 由 Adapter 自己排空。
- 稳定分支原版 RTL 不应覆盖或重写；V0.6 通过之后，在双方接口定稿前仍不能声称 V1.0 彻底冻结。
- 除非经过验证，勿将测试参考模型作为可下载 FPGA 顶层；独立模块的 IOB 超限问题仍需等 CPU 板级顶层集成解决。

## 验收与协作

在 `feature/if-fetch-integration` 上提交三个新增测试文件及本 README，截取 `CASE 1...CASE 9` 和最终 `ALL TESTS PASSED` 的 Vivado 画面；请求队员 A 对照其正式 IF Controller 接口，联合确定最终 V1.0。**正式 IF 控制器由队员 A 开发**，本测试参考不是他的交付物。
