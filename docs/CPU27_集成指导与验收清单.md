# 27 条指令正式单周期 CPU 集成包（V0.1）

**基线：**原 `rtl/common/cpu_top.v`（18 指令，使用 `decoder_v2`），以及队员 A PR #6 `decoder.v`（27 指令）。

## 改了什么

- `rtl/common/cpu_top.v`：**仅**把 `decoder_v2 u_decoder` 切换为 `decoder u_decoder`，并更新过时注释；其余连接、端口、时序行为完全不变。原版在 `reference/cpu_top_before_integration.txt`。
- `tb/tb_13_instructions.v`：复制原 B 的 13 指令专项测试（原日志 872 checks）。
- `tb/tb_cpu_top_smoke.v`：复制原单周期 CPU 基线回归（原日志 397 checks）。
- `tb/tb_cpu27_arith9.v`：从 A 的 `tb_cpu_arith_9_instructions.v` 改编，**正式 DUT 设为 cpu_top**（A 原日志 657 checks）。
- `tb/tb_cpu27_branch_regression.v`：从 A 的 `tb_cpu_arith_regression.v` 改编，正式 DUT 同样设为 cpu_top。
- `tb/tb_cpu27_unified.v`：新增 27 种指令**真实混合执行**的自检测试（算术、逻辑、比较、变量/立即数移位、存储器、五种分支、跳转链接、跳过错误路径、非法指令、r0、防停顿时误写）。
- `docs/cpu27_program.csv` 和 `docs/cpu27_expected_trace.csv`：程序及逐指令期望值，来自独立 Python 指令语义参考模型。
- `reference/decoder_PR6_snapshot.txt`：队员 A 本次提交 decoder.v 内容快照；不是 Vivado 设计源文件！正式综合仍应使用合并到 main 的 `rtl/common/decoder.v`。

## 分支及 GitHub Desktop 步骤

1. **必须先确认 PR #6 已真实合并进 main**；这一步此包无法代替。假如还没合并，不要在旧 main 上直接覆盖。
2. 在 GitHub Desktop：Fetch origin → 切换 main → Pull origin → New branch，输入 `feature/cpu27-integration`。
3. 将包中的 `rtl/common/cpu_top.v` 放入本地项目同路径；替换前确认现有文件与参考旧版没有重要新增改动。不要把 reference/*.txt 加入 Design Sources。
4. 复制 `tb/` 下测试文件；如果原 `tb_13_instructions.v` 与 `tb_cpu_top_smoke.v` 未改过，无需覆盖。
5. 确认 Vivado Design Sources 实际加载 **合并后的** `rtl/common/decoder.v`，不能同时添加第二个同名 `module decoder`。
6. `cpu_top_arith_test.v` 作为队员 A 的**临时**测试模块可以保留，但下面的新 TB 均不需要依赖它。`decoder_v2.v` 同样作为历史对照保留。
7. 逐项设置 Simulation Top 并 Run Behavioral Simulation → Tcl `run all`；每次保存终端包含 Total checks/errors 的截图。不同 TB 不要同时设 Top。

## 推荐验证顺序

| 顺序 | Vivado Simulation Top | 作用 | 已有历史成绩（正式整合后仍需重测） |
|---|---|---|---|
| 1 | `tb_13_instructions` | 保证 B 的原 13 指令未破坏 | 872 checks, 0 errors |
| 2 | `tb_cpu_top_smoke` | 保证 5 分支/访存旧 CPU 回归 | 397 checks, 0 errors |
| 3 | `tb_cpu27_branch_regression` | 以正式 cpu_top 重测 A 的兼容性回归 | A 报告 0 errors |
| 4 | `tb_cpu27_arith9` | 以正式 cpu_top 重测 A 的 9 指令 | A 报告 657 checks, 0 errors |
| 5 | `tb_cpu27_unified` | **新增**真正 27 类指令混合整机验收 | 尚未执行 Vivado；以实际日志为准 |

`tb_cpu27_unified` 用机器码、预期 PC、控制信号、写回值和最终寄存器/数据存储器状态交叉验收，**不能仅因参考模型已通过就写成 RTL 已通过**。

## 所需既有设计模块

来自 main 的：`decoder.v`（PR #6）、`cpu_defs.vh`、`imem.v`、`imm_gen.v`、`dmem.v`、队员 A 的 `alu.v` / `regfile.v` / `pc_reg.v` / `branch_unit.v`。

**不要把 I-Cache 连接进本次单周期 CPU！** 不要同时修改 A 的 Decoder；缓存与五级流水线接口在此阶段暂不冻结。

## 限制与后续验收

- 本包按已有文件进行静态检查与独立 Python 指令语义参考模型验证；本环境没有 Vivado/iverilog，**没有独立完成 RTL 仿真**。
- 为保持对照，`cpu_top.v` 仍是单周期、组合 IMEM/DMEM 设计，不包含 IF/ID 流水寄存器、旁路、冒险处理、I-Cache 或板级封装。
- 在正式 `main` 合并前，用 PR 的源码快照不等同于最新 PR head 的 GitHub 审批。
- 跑完五套测试后，将 Vivado 日志发回，即可核对结果、修复问题并准备集成 PR。
