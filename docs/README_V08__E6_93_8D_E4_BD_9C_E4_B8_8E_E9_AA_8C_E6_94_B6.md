# V0.8 取指 + 流水线总控制联调（Vivado 2019.1）

## 1. 本次交付边界

新增、仅新增两个 Verilog-2001 文件：

- `rtl_test_only/ifetch_pipeline_control_v08.v`：将正式 `pipeline_control_unit` 接到已合并的 V0.7 取指连接层；这是仿真专用的联合测试封装，**不是**五级流水线 CPU 顶层。
- `tb/tb_ifetch_pipeline_control_v08.v`：共 **18 类场景**（继承 V0.7 的 12 类场景并增加 6 类 V0.8 场景）；每周期检查 PCU 四个输出及 IF/ID 状态，检查握手和 PC 一致性。**检查总数在本地 Vivado 跑完后以实际报告为准**，不等于 V0.7 的 1549 项。

不要修改：`cpu_top.v`、`decoder.v`、正式 `pc_if_controller.v`、`if_id_reg.v`、`pipeline_control_unit.v`、`icache_if_adapter.v`、`icache_2way_latency.v`、`imem_latency.v`、`ifetch_subsystem_v07.v`。

## 2. 先验证 Git 分支与源码

在 GitHub Desktop，确认当前分支为 `feature/if-pipeline-control-v08`，分支由已同步的 `main` 建立。

确认主仓库已经有：

```
rtl/common/pipeline_control_unit.v
rtl/common/pc_if_controller.v
rtl/common/if_id_reg.v
rtl/memory_cache/icache_if_adapter.v
rtl/memory_cache/icache_2way_latency.v
rtl/memory_cache/imem_latency.v
rtl_test_only/ifetch_subsystem_v07.v
```

## 3. 将新增文件放入本地目录

复制本压缩包的 `rtl_test_only` 和 `tb` 下两个新文件到：

```
D:\CPU_Project\LoongArch-Pipeline-CPU\rtl_test_only\ifetch_pipeline_control_v08.v
D:\CPU_Project\LoongArch-Pipeline-CPU\tb\tb_ifetch_pipeline_control_v08.v
```

用 VS Code 查看是否都是 UTF-8 普通文本 `.v` 文件，不要保存成 `.v.txt`。

## 4. 在 Vivado 2019.1 添加文件（不重复添加旧 RTL）

1. 打开之前已经成功运行 V0.7 的 `.xpr` 工程。
2. **Add Sources -> Add or Create Design Sources -> Add Files**，选择 `rtl_test_only/ifetch_pipeline_control_v08.v`。（也可作为 Simulation Sources，但必须在 sim_1 编译中可用。）
3. **Add Sources -> Add or Create Simulation Sources -> Add Files**，选择 `tb/tb_ifetch_pipeline_control_v08.v`。
4. 进入 Sources -> Simulation Sources，找到 `tb_ifetch_pipeline_control_v08`，右键 **Set as Top**。
5. 保持其余正式源码在工程内可见，不要添加 `baseline_v06/` 或重复的 reference 模块。

Tcl Console 可执行：

```tcl
set_property top tb_ifetch_pipeline_control_v08 [get_filesets sim_1]
update_compile_order -fileset sim_1
report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
```

**预期编译层级含九个文件**：

- `rtl/common/pc_if_controller.v`
- `rtl/common/if_id_reg.v`
- `rtl/common/pipeline_control_unit.v`
- `rtl/memory_cache/icache_if_adapter.v`
- `rtl/memory_cache/icache_2way_latency.v`
- `rtl/memory_cache/imem_latency.v`
- `rtl_test_only/ifetch_subsystem_v07.v`
- `rtl_test_only/ifetch_pipeline_control_v08.v`
- `tb/tb_ifetch_pipeline_control_v08.v`

要求 `Missing instances` 为 `< empty >`。若列表缺文件，先检查实际磁盘路径和 Vivado Sources 引用，不要复制参考模块顶替。

## 5. 运行

关闭旧 Behavioral Simulation 再启动新的，或者点击 Run Simulation -> Run Behavioral Simulation。进入 Tcl Console 后：

```tcl
run all
```

测试有 100us 的硬性超时保护。如果出现 `FAIL`、`FATAL TIMEOUT`、`TESTS FAILED` 或 Compile / Elaborate 错误，**不要提交已通过**；将第一条 FAIL、完整编译顺序和报错上下文发给助手进行定位。

测试成功时会输出：

```
V0.8 OFFICIAL IF + PIPELINE CONTROL INTEGRATION TEST
Total scenarios = 18 (V0.7 regression 12 + V0.8 control 6)
Total checks = ...               // 实测后确定，不要预填
Total errors = 0
Total requests = ..., responses = ...
Total valid deliveries = ..., error responses = 1
ALL TESTS PASSED
```

上面的内容是**验收条件，不是已经运行的结果**。本交付环境没有 Vivado 或 HDL 仿真器，**未宣称已通过 V0.8**。

## 6. 这次相对 V0.7 的差异与注意事项

控制连线：

```
ifid_stall                 = PCU 输出
ifid_flush_ctrl            = PCU 输出
idex_flush                 = PCU 输出（只监测；尚未接真实 ID/EX）
hold_fetch_issue_req       = PCU 输出（只监测；不影响 IF request valid）
id_can_advance_effective   = id_can_advance_external && !ifid_stall
ifid_flush_effective       = ifid_flush_external || ifid_flush_ctrl
branch_redirect            -> 同时送 PCU 和 V0.7/Adapter
```

在有效 Redirect 或 Reset 时，旧取指会通过已有 PC Controller + Adapter 的协议处理；**普通 Load-use 不允许取消 Cache 已接受或 IF 尚未握手的请求**。

第一阶段支持的是 IF/ID 的 Stall/Flush 和控制优先级联合验证，不含真正 ID/EX / EX/MEM / MEM/WB、BL/JIRL 结果写回、数据 Cache、多周期 MEM 反压，也**没有完全实现按 `hold_fetch_issue_req` 停发全新请求的优化**。不能把 V0.8 通过解释为整机 CPU 完成。

## 7. GitHub Desktop 提交与证据

如果仿真通过：

1. 将控制台截图和波形图保存在 `docs/evidence/v08/`；将 `report_compile_order` 输出保存为文本文件。
2. 回到 GitHub Desktop，确认 Changes 仅包含新增 V0.8 文件/证据，不要误改旧 RTL。
3. Commit Summary：`test(if): integrate pipeline control with V0.7 fetch harness`
4. Commit -> Push origin -> Create Pull Request，base=`main`，head=`feature/if-pipeline-control-v08`，交队员 A 审核。

请注意 Vivado `.xpr`、`.sim`、`.cache`、`.runs` 等本地生成物通常不应随测试源代码提交。
