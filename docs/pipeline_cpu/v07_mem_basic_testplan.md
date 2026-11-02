# V0.7 多周期 Data Memory + I-Cache 整机集成测试计划

> 状态：**候选实现，尚未执行 Vivado 2019.1 仿真**。本包不含任何成功截图，所有数字仅为预期值，不能作为实际验证结果。

## 新增范围

- `rtl_test_only/pipeline_cpu_core_v07_mem.v`：基于 V0.5 的 PC/IF、I-Cache、Adapter 外部连接，新建独立整机顶层。
- `rtl_test_only/pipeline_cpu_core_v07_mem_datapath.v`：基于 V0.4 数据通路，在 **新文件** 内接入正式 `dmem_latency.v`，控制 MEM 等待、上游暂停、EX 分支一次性解析和 WB 单次提交。
- `tb/pipeline_cpu/tb_pipeline_cpu_v07_mem_basic.v`：第一版联合仿真、事务检查及顺序 Scoreboard。
- `tb/pipeline_cpu/programs/v07_mem_basic.mem`：18 条真实 LoongArch 指令。
- `docs/pipeline_cpu/v07_mem_basic_program_map.csv`：机器码、虚拟/物理地址、预期效果。

**不修改**：正式 `dmem_latency.v`、旧 `dmem.v`、V0.1～V0.6、V0.9、正式 Cache/Adapter、PC/IF、CPU27 等稳定模块。

## 接口/握手契约

- I-Cache/IMEM 复用 V0.5 的 0x1000 虚拟 PC → 0x0 物理地址映射。
- DMEM 地址是独立的**字节地址**，范围 0～1023，LD.W/ST.W 按 4 字节对齐。
- `req_fire = req_valid && req_ready`：CPU 只发出一次事务请求；等待接受时 EX/MEM 保持有效负载。
- `resp_fire = resp_valid && resp_ready`：Load 在握手后进入 MEM/WB；Store 在正式 DMEM 内部的该握手沿真正写入。
- 响应未完成时 EX/MEM、ID/EX、IF/ID 保持；上游 `if_ready=0`，已到达的 I-Cache 响应由 Adapter 保持。
- MEM/WB 不跟着 MEM Stall 保持旧 valid：旧 WB 在最初一个 stall 周期提交，下一拍转换为 bubble，防止重复提交。
- EX 冲突且数据尚在 EX/MEM 的 Load 时额外插入一拍等待/EX-MEM bubble，避免在 Load 的响应完成沿使用旧地址当作值。
- Branch 仅在 EX 允许推进时发出有效 Redirect，冻结期间不会重复 Redirect。
- `mem_fault_valid` 在错误响应握手时单周期有效。该版本屏蔽出错 Load 的 WB，但**没有实现异常入口**。

## 基础测试场景与预期参考

- `0x1000` / `0x1004`: 初始化 `r1=10`, `r2=20`。
- `0x1008`: Store `[4]=10`；`0x100c`: Load `r3=10`；`0x1010`: ADD `r4=r3+r2=30`。
- `0x1014`: Store `[8]=30`；`0x1018`: Load `r5=30`；`0x101c`: ADDI `r6=31`。
- `0x1020`: `BEQ r6,r6,+12`，跳转到 `0x102c`；`0x1024` 的 Store、`0x1028` 的 WB 都是错误路径，应当抑制。
- `0x102c`: Load `r8=30`；`0x1030`: ADDI `r9=32`；`0x1034`: Store `[16]=32`。
- `0x1038`: Load `r10=32`；`0x103c`: ADDI `r11=31`。
- `0x1040`: 非法指令被过滤；`0x1044`: `ADDI r0` 不允许实际写入。

**预期计数**：WB 10 次、Store 3 次、DMEM req/resp 各 7 次、Branch Redirect 1 次、错误路径 Store/WB 为 0、MEM Stall 周期数 >0、错误数 0。

每一笔 WB 比较 PC、rd、data；每一笔 Store 比较 PC、地址、数据；结束后检查 `DMEM[1]=10`、`DMEM[2]=30`、`DMEM[3]=0`、`DMEM[4]=32` 以及 `r7=0`。

## 本阶段还未覆盖

- MEM 等待时 **外部强制响应背压** 与最大延迟。
- Redirect 与 MEM Stall/IF Cache Miss 同一时刻的可控冲突。
- DMEM 错误访问的整机异常响应，Reset 中止事务的整机检查。
- 多周期环境下全部 27 指令、长时间随机压力、硬件时序/综合、FPGA 上板。

以上必须由后续独立回归进一步验证，不能把第一版基础测试称为最终全部通过。

## 仿真操作与验收

1. 先从最新 `feature/pipeline-cpu-integration`（包括已合并 PR #30）创建 `feature/pipeline-v07-mem-integration`。
2. 加入**两个新增** `rtl_test_only/*.v` 作为 Design Sources，新 Testbench 作为 Simulation Sources。原有各源保持不变，尤其仅加入**一个** `dmem_latency` 模块定义。
3. 保留 V0.5/V0.4 依赖（正式 `decoder`,`regfile`,`alu`,`imm_gen`,`forwarding_unit`,`load_use_hazard_unit`,四个流水线寄存器，`branch_resolve_v04`，`pc_if_controller`,`pipeline_control_unit`,`icache_if_adapter`,`icache_2way_latency`,`imem_latency`）。
4. 选择 `tb_pipeline_cpu_v07_mem_basic` 为 Simulation Top，Run Behavioral Simulation，Tcl `run all`。
5. 不修改已测试成功的其他 TB/RTL。如遇错误，保存完整 FAIL 行、波形、compile/elaborate/simulate.log。
6. `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`，确认 Missing instances 为空。
7. 仅在实际出现 `ALL TESTS PASSED` 且 `ERRORS=0` 后保存日志、截图和提交 PR。PR Base=`feature/pipeline-cpu-integration`。
