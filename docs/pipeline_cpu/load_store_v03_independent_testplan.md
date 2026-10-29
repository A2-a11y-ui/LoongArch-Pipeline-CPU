# V0.3 Load/Store + Load-use 独立整机回归（第二阶段）

## 版本与验证边界

- 正式 DUT：`rtl_test_only/pipeline_cpu_core_v03.v`，已核对 A 的 `feature/pipeline-cpu-integration` 分支正式端口。
- 环境：Vivado 2019.1；Verilog-2001；仅允许 4 字节对齐、0～1023 字节内的访问。
- 本包中**只包含新增 Testbench、独立机器码和可审核的测试预期**，不替换或改动任何正式 RTL。
- **不是 A 的原始测试**：本包独立构造 60 条指令；ISA 参考计算得出 43 次预期 WB、14 次 ST.W、2 条预期过滤（非法指令和 B）、一次写 r0 被屏蔽。设计目标不代表已通过仿真。
- DMEM 初值不确定：本程序中每次 LD.W 都在相应地址被 ST.W 初始化后才执行。

## 测试目录

- `tb/pipeline_cpu/tb_pipeline_loadstore_independent_v03.v`：可直接连接真实 V0.3 顶层；包含 IF ready/valid 驱动、WB/Store 双记分板、覆盖统计及超时保护。
- `tb/pipeline_cpu/programs/load_store_v03_independent.mem`：60 条十六进制机器码，ROM[0] 对应 PC 0x1000，逐字节地址加 4。
- `docs/pipeline_cpu/load_store_v03_independent_map.csv`：每条指令 ISA 参考结果和存储器事件。

## 关键握手协议

- 仅当正沿 `if_valid && if_ready` 时将 ROM 索引加 1；当 `!if_ready` 时**持续提供同一条 `if_pc` 和 `if_inst`**；不推进 PC，也不能吞掉或重复送指令。
- CPU 在 ID 检测 Load-use 时，保持 IF/ID、清除 ID/EX 的年轻指令，同时旧 Load 继续流向 EX/MEM。
- 以每个上升沿**之前**的 `wb_commit_valid` 和 `mem_store_commit_valid` 为准逐笔核对，因为 RegFile/DMEM 都在同一正沿实际写入。
- 访问值以黑盒公开 Store/WB 事件为主判断，不直接覆盖 DUT 内部 RAM。

## Vivado 操作

1. PR #24 已合并，建议从最新 `feature/pipeline-cpu-integration` 创建新分支 `feature/pipeline-v03-loadstore-verification`：GitHub Desktop → Fetch origin → 切到 integration → Pull origin（若出现）→ Current branch → New branch。此举避免重用已完成 PR 的旧分支。
2. 将 `tb/`、`docs/` 合并复制到 `D:\CPU_Project\LoongArch-Pipeline-CPU\`；不要多嵌套一层目录。
3. Add Design Sources：`rtl_test_only/pipeline_cpu_core_v03.v`、`rtl/memory_cache/dmem.v`，加上已有 `decoder.v`、`regfile.v`、`imm_gen.v`、`alu.v`、`forwarding_unit.v`、`load_use_hazard_unit.v`、`if_id_reg.v`、`id_ex_reg.v`、`ex_mem_reg.v`、`mem_wb_reg.v`。避免重复添加。
4. Add Simulation Sources：`tb/pipeline_cpu/tb_pipeline_loadstore_independent_v03.v`。
5. Tcl Console：

   ```tcl
   set_property top tb_pipeline_loadstore_independent_v03 [get_filesets sim_1]
   report_compile_order -of_objects [get_filesets sim_1] -used_in simulation
   ```

6. 确认 `Missing instances for 'simulation': < empty >`，执行 **Run Behavioral Simulation**。Vivado 会自动执行仿真；若出现 `$finish` 不要再用 `run all`。
7. 检查预期结果：

   ```text
   RESULT: words=60 issued=60 WB=43/43 STORE=14/14 unsupported=2 stalls=... errors=0
   ALL TESTS PASSED (V0.3 independent full CPU)
   ```

8. 如果失败，先核对首次 `FAIL WB` / `FAIL STORE` 的 PC、rd、data；不要修改 A 的正式 CPU。将日志及波形发回核验。

## 独立场景覆盖

- ALU->ST.W 数据前递；ST.W->LD.W 的存储器可见性。
- LD.W->ADDI、LD.W->ADD（含同一寄存器双源）、LD.W->ST.W 数据及基址依赖。
- 寄存器多次连续覆盖最新值优先；WB->ID；r0 写回屏蔽、r0 作 Store 数据。
- 正负立即数偏移、非零基址、负数 LD/ST、二次覆盖同一 DMEM word。
- 未支持的非法指令与 B：无 WB、无 Store、仍能继续执行后继指令。
- 无指令丢失与重复：60 次 accepted IF + 每笔 WB/Store 精确顺序校验。

## 独立验证后的提交建议

保存 `v03_loadstore_independent_pass.png` 和 `v03_loadstore_independent_compile_order.txt` 到 `docs/pipeline_cpu/evidence/`；只对这几个新增文件做 Commit/Push。新 PR 的 **base** 是 `feature/pipeline-cpu-integration`，**compare** 是 `feature/pipeline-v03-loadstore-verification`。如 PR 混入历史改动，先检查分支创建基点和 Files changed。

## 注意

V0.3 不验证 I-Cache 延迟/Redirect、Branch 执行、多周期内存总线、Cache Miss/反压、非对齐访问和异常；不能用本轮 PASS 替代这些功能验收。
