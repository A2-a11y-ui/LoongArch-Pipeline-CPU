# CPU V0.4 Branch Redirect — 第二阶段独立整机回归

## 目标与基线

- A 正式顶层 `rtl_test_only/pipeline_cpu_core_v04.v`（GitHub Commit `b51a0d3`）。
- 本次测试程序**不是** A 的 `branch_v04.mem`：它是独立编写的 **65 个机器码字**，参考结果来自基于人类可读汇编程序的独立软件语义模型。
- 预期 29 次有效 WB、8 次有效 Store、15 次分支解析，其中 taken 10、not taken 5、不支持指令 2。
- 尚未在你的 Vivado 2019.1 中实际运行，以上为**预期**，不是声称通过的实测结果。

## 文件

- `tb/pipeline_cpu/tb_pipeline_branch_independent_v04.v`：外部 IF ready/valid 驱动，WB / Store / Branch 3 套逐笔 Scoreboard，Load-use、Redirect 后流水线状态检查。
- `tb/pipeline_cpu/programs/branch_v04_independent.mem`：65 条真实 LA32 机器码。
- `docs/pipeline_cpu/branch_v04_independent_map.csv`：逐行 PC / 指令 / 动态执行次数及 Wrong Path 标记。
- 本测试计划。

## 特别重要的握手约束

1. **Load-use Stall**：`if_ready=0`，保留指令索引，在下个上升沿重试当前字。
2. **Branch Redirect**：`if_ready=0`，但当前错误路径字应**取消**而不是重试；在该时钟沿直接将 IF 索引改为 `branch_redirect_pc` 对应 ROM 位置，下一次下降沿提供目标指令。
3. **Branch 解析**：`branch_resolve_valid` 包含 BEQ/BNE 不跳转；仅 `branch_redirect=1` 才发生 Flush。
4. 检查 Wrong Path Store 地址 `64..92` 不允许触发 Store 提交；错误路径 WB 不得出现在提交序列。
5. BL/JIRL 提交值必须等于该分支自身 PC+4；JIRL 目标来自 rs1+offs16 并清除 bit0。

## 操作

1. GitHub Desktop 从最新 `feature/pipeline-cpu-integration` 新建 `feature/pipeline-v04-branch-integration-verification`；不要直接修改 main。
2. 将 ZIP 中 `tb`、`docs` 放入 `D:/CPU_Project/LoongArch-Pipeline-CPU`，**不覆盖** V0.1～V0.3 或旧的 Branch Unit 文件。
3. 在 Vivado 添加 Design Sources：`rtl_test_only/pipeline_cpu_core_v04.v`、`rtl_test_only/branch_resolve_v04.v`，以及官方 Decoder、ImmGen、ALU、RegFile、Forwarding、Load-use、DMEM、IF/ID、ID/EX、EX/MEM、MEM/WB；已有的勿重复添加。
4. 添加 Simulation Source：`tb/pipeline_cpu/tb_pipeline_branch_independent_v04.v`。
5. Tcl Console：

```tcl
set_property top tb_pipeline_branch_independent_v04 [get_filesets sim_1]
update_compile_order -fileset sim_1
report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
```

6. 确认 `Missing instances` 为空，点击 Run Behavioral Simulation，正常 `$finish` 之后**不要额外输入** `run all`。
7. 目标输出为 `WB=29/29`、`STORE=8/8`、`BR=15/15`、`errors=0`、`ALL TESTS PASSED`。
8. 通过后只保存 `docs/pipeline_cpu/evidence/v04_branch_independent_pass.png`，然后 Commit / Push / PR 到 `feature/pipeline-cpu-integration`。**不要求提交编译顺序 TXT**。

## 验证边界

本测试为 V0.4 **流式 IF + 单周期 DMEM** 的真实整机回归；不代表 I-Cache Miss、真正 request/response 总线、跨 Cache Redirect、非对齐访存或全部 27 条指令已经集成验证。Load-use/Redirect 优先级在当前顶层仍受单个 EX 分支和 ID 使用者的结构约束，未模拟无法到达的组合事件。
