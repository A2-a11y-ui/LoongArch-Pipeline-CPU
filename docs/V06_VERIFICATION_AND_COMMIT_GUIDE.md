# V0.6 取指子系统联合仿真——验收记录及 PR 提交说明

项目：LoongArch-Pipeline-CPU  |  日期：2026-10-28  |  开发环境：Vivado 2019.1

## 1. 已有实测结果（用户提供的 Vivado 截图）

- 仿真顶层 `tb_ifetch_subsystem_v06`
- `Total errors = 0`
- `Total requests = 24, responses = 12`
- `Total valid deliveries = 11, error responses = 1`
- 最后统计区间：`hits=0 misses=2 refill_words=8 backing_words=8`
- `ALL TESTS PASSED`
- 仿真结束约 3311 ns
- 用户明确确认使用的 `if_id_reg.v` 为队员 A 正式版本。

注意：24 个请求和 12 个响应是跨多个 Reset/Redirect 场景的累计量，取消请求不能按正常响应一一对应；最后的 hits/misses 是最后统计区间，不能据此得出全程命中率。

## 2. 这次 PR 应该新增哪些文件

- `rtl_test_only/if_pc_driver_v06.v`：**仅用于仿真**的 PC 请求参考驱动；不是 A 的正式流水线 PC 控制单元。
- `rtl_test_only/ifetch_subsystem_v06.v`：V0.6 联合仿真连接顶层；不是正式 CPU/FPGA top。
- `tb/tb_ifetch_subsystem_v06.v`：9 个场景 + 时钟沿检查的自检 Testbench。
- `docs/V06_验收记录_及提交说明.md`：过程记录。
- `docs/V07_正式PC控制器_接口交接清单.md`：下阶段接口确认事项。
- 可另行在 `docs/` 归档本次 Vivado 截图。

**不要**提交参考替身 `if_id_reg_A_reference.v`，因为已经使用 A 的正式文件。不要重复提交或覆盖现有的 `rtl/common/if_id_reg.v`、`rtl/memory_cache/icache_if_adapter.v`、`icache_2way_latency.v`、`imem_latency.v`、`cpu_top.v` 和 `decoder.v`。

## 3. GitHub Desktop 操作

1. 首先核实 PR #9（I-Cache Adapter）和 PR #10（架构讨论规范）实际合并状态；若主分支未包含依赖模块，应先协调合并。不要仅因 PR 已创建就认为已在 main。
2. GitHub Desktop 在 main 分支 `Fetch origin`/`Pull origin`，确认网络同步成功；如果 Pull 失败，不要以旧 main 当最新基线。
3. 从同步后的 main 创建新分支 `feature/if-fetch-integration`。
4. 将这次 PR 包内两个 `rtl_test_only/` 文件、一个 `tb/` 文件及两份 `docs/` 文件复制进仓库根目录对应位置。对仓库里已存在的同名文件以 diff 确认，不盲目覆盖。
5. 先在 Vivado 重新核对 `tb_ifetch_subsystem_v06`、A 正式 `if_id_reg.v` 和 Cache/Adapter；结果应与已提供截图一致。
6. GitHub Desktop 核对 Changes：仅出现新增测试驱动、测试子系统、TB 和 docs，不得意外修改正式 CPU 或 Cache。
7. Commit Summary：`test(if): verify V0.6 fetch subsystem with official IF/ID register`；然后 `Push origin`，创建 PR 指向 main。
8. 将 `docs/PR_描述_可直接复制.md` 的内容复制到 GitHub PR 描述，邀请队员 A Review。

## 4. V0.6 验收范围与限制

已由 V0.6 Testbench 覆盖：顺序 fetch、Miss/Stall、Redirect 排空、响应持有、回填完成沿 Redirect、Flush/Stall、Reset 优先级、错误响应、Redirect+Stall+Flush。

**未完成：** 队员 A 正式 PC/IF 控制器的替换验证；完整五级流水线、实际 27 条指令流水执行、FPGA 实现和时序收敛；不能以本次 V0.6 通过替代上述验收。

## 5. 下一阶段停止条件

在队员 A 提供正式 PC/IF 模块的端口声明、RTL 和独立测试结果之前，不修改 `if_pc_driver_v06.v` 充当正式实现；应在独立新集成顶层中实例化 A 的正式模块并复用 V0.6 9 组场景，新增连续 Redirect、PC 只发一次、无错序、Backpressure 恰好一次的检查。
