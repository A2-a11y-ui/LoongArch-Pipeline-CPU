# CPU V0.3 Load-use 独立验证（第一阶段）

## 当前基线与限制

- 2026-10-29 GitHub 核对：PR #23 **Merged** 至 `feature/pipeline-cpu-integration`；V0.2 双方回归已完成。
- 仓库存在正式 `rtl/common/load_use_hazard_unit.v` 和 `rtl/common/pipeline_control_unit.v`、`rtl/common/if_id_reg.v`、`rtl/common/id_ex_reg.v`。
- 核对时集成分支 **尚无** `rtl_test_only/pipeline_cpu_core_v03.v`，也尚未确认真实 DMEM / load-result ready 接口。
- 该测试包 **未修改任何正式 RTL**，仅添加两个 Verilog-2001 独立 Testbench。禁止将这些测试结果当作 V0.3 整机 LD.W/ST.W 已完成的证据。

## 文件与覆盖

| 路径 | 目的 | 预期规模 |
|---|---|---|
| `tb/pipeline_cpu/tb_load_use_hazard_v03.v` | 测试正式 Load-use Hazard Unit 的四个输出 | 30 cases、120 checks |
| `tb/pipeline_cpu/tb_load_use_control_v03.v` | 使用正式 IF/ID、Decoder、ImmGen、ID/EX、Load-use 单元、PCU，测试冻结、气泡、恢复以及 redirect > load-use、reset 优先级 | 13 phases、130 checks |

测试重点包括：rs1/rs2 单独或同时依赖；used 位屏蔽；r0 目的寄存器屏蔽；ex_valid、id_valid、mem_read 门控；依赖消失后释放；IF/ID 保持 PC 与指令；ID/EX 插入气泡；分支重定向高优先级清空。

## Windows / Vivado 2019.1 操作

1. GitHub Desktop **Fetch origin**，切换最新 `feature/pipeline-cpu-integration` 并 Pull；再创建新分支 `feature/pipeline-loaduse-verification`（从 integration 创建，不要在旧 V0.2 verification 分支上开发）。
2. 将本包 `tb/`、`docs/` 两个文件夹合并到 `D:\CPU_Project\LoongArch-Pipeline-CPU\`，只新增对应文件。
3. 第一轮：Add Design Sources 加入 `rtl/common/load_use_hazard_unit.v`（若已加入则无需重复）；Add Simulation Sources 加入 `tb/pipeline_cpu/tb_load_use_hazard_v03.v`。
4. Tcl Console：
   ```tcl
   set_property top tb_load_use_hazard_v03 [get_filesets sim_1]
   report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
   ```
   确认 `Missing instances` 为空，再 Run Behavioral Simulation。
5. 第二轮：Add Design Sources 确保 `pipeline_control_unit.v`、`if_id_reg.v`、`id_ex_reg.v`、`decoder.v` 和 `imm_gen.v` 都已加入，同时确认 `cpu_defs.vh` 可被 decoder 解析；Add Simulation Sources 加入 `tb_load_use_control_v03.v`。
6. Tcl Console：
   ```tcl
   set_property top tb_load_use_control_v03 [get_filesets sim_1]
   report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
   ```
   再 Run Behavioral Simulation。仿真 `$finish` 后无需额外 `run all`。
7. 两轮全部通过后保存：
   - `docs/pipeline_cpu/evidence/v03_hazard_unit_pass.png`
   - `docs/pipeline_cpu/evidence/v03_loaduse_control_pass.png`
   - `docs/pipeline_cpu/evidence/v03_hazard_compile_order.txt`
   - `docs/pipeline_cpu/evidence/v03_control_compile_order.txt`
8. 提交至新 verification 分支，推荐 commit message：`test(cpu): add V0.3 load-use preintegration regressions`。可以先 Push 保存，**先不提 V0.3 整机验收 PR**。

## 待队员 A 提供 V0.3 正式顶层后完成

请与 A 对齐：顶层名、IF 发射是否有 ready/valid 反压、暂停时待发指令如何保留、DMEM 端口及数据时序、LD.W 何时结果 ready、WB 提交是否有握手，以及对不支持指令如何处理。

届时独立整机验证必须进一步覆盖：

- LD.W → ADD.W、LD.W → ADDI.W、LD.W → ST.W 等紧邻依赖，期望正确 Stall 和唯一写回；
- 仅 rs1 / 仅 rs2 / 双源相关、无关指令不误暂停；
- Load-use 与 Forwarding 同时存在时选择最新可用数据，不允许用未就绪的 EX/MEM 结果；
- 分支 Redirect 与 Load-use 冲突时不保留错误路径的指令；
- 可变 DMEM 延迟、暂停恢复、不丢失/重复发射、不丢失/重复写回；
- 提交顺序 PC、rd、data、写回数量及最终存储器内容均与独立 Golden Model 一致。

**不要在尚未知晓 V0.3 DMEM 和 IF 握手协议时凭空编造整机机器码通过成绩。**
