我已完成 V0.6 联合测试，确认使用的是你正式提交的 IF/ID Register，Vivado 2019.1 结果为 0 错误、ALL TESTS PASSED。PR #11 已创建，准备完成审核与合并。

我现在启动 V0.7 的**测试准备**，不修改已通过测试的 Adapter V0.5.1 与两路 LRU I-Cache。

请你继续开发 Load-use Stall，并在正式 PC/IF 控制器完成时提供：
1. RTL 文件、module 名称和完整端口声明；
2. RESET_PC、req_fire 后的 PC 更新、Redirect 目标保存逻辑；
3. Miss/DRAIN 期间目标 PC 如何保持、Stall/Flush/Redirect 如何协同；
4. 独立 Testbench、仿真结果及对应 PR。

收到正式 PC/IF RTL 后，我将基于 V0.6 新增 V0.7 连接顶层和 TB，沿用顺序取指、Miss、Stall、Flush、Redirect、Reset 等回归场景，再补充重定向和反压交叉测试；不直接拿测试用 `if_pc_driver_v06.v` 冒充正式模块。
