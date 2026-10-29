# Pipeline CPU V0.1 算术独立回归计划

## 基线及范围
- A 正式提交：`13e02c2`，`rtl_test_only/pipeline_cpu_core_v01.v`。
- 测试平台：`tb/pipeline_cpu/tb_pipeline_cpu_basic.v`；ROM：`tb/pipeline_cpu/programs/arithmetic_basic.mem`。
- 顶层 `pipeline_cpu_core_v01` 外部 IF 端口：clk/rst/if_valid/if_pc/if_inst；WB：wb_commit_valid/wb_commit_pc/wb_commit_rd/wb_commit_data；诊断 id_unsupported/id_raw_hazard。
- 本阶段不接 I-Cache、分支、DMEM 和 Forwarding，不能用本测试证明全部 27 条指令正确。

## 测试流程
1. 同步 Reset 保持两个上升沿。
2. `$readmemh` 读入 **24 条**已知机器码，ROM[0] 对应 PC `0x1000`，后续依次 +4。
3. 输入前 13 条；然后 `if_valid=0` 插入六个 Bubble（不推进 PC、ROM 索引）。
4. 输入剩余 11 条；最后 10 个 Bubble 排空流水线。
5. 监听每个正沿的 `wb_commit_valid`，比较当拍 WB PC、目的寄存器号和数据。Testbench 在寄存器非阻塞更新之前观察 WB，符合当前同步 RegFile 写入行为。
6. 统计 `id_unsupported=4`（非法码、LD.W、ST.W、B），`id_raw_hazard=0`；验证 r0 不被写、关键寄存器终值。

## 预期
- 提交 19/19；unsupported=4；hazards=0；errors=0；ALL TESTS PASSED。
- A 的原始 V0.1 检查是在 Vivado 2019.1 完成的；本独立回归必须在本机重新运行，不能把 A 的成功当作独立回归通过。

## 重要：文件来源、分支操作
- 从 A 的 `feature/pipeline-cpu-integration` **读取**最新 top，不能未经核查地覆盖自己分支里的文件。建议等 A 的 PR 合并 main 后再合并 main 到 `feature/pipeline-cpu-verification`；如需立即跑，可单独把正式 `pipeline_cpu_core_v01.v` 下载到仓库 `rtl_test_only/`（注意 PR 中不要重复提交 A 的顶层）。
- 本包仅替换你先前建立的 3 个测试文件；不要改 `cpu_top.v`、Decoder、RegFile 或四组正式流水线寄存器。
- 此包使用已核实的机器码 24 字；以前未对应正式 V0.1 的 138 字、21 次提交版本请不要继续用于当前基线验收。

## Vivado 2019.1
- 添加正式 CPU 顶层和其依赖的 Decoder、RegFile、ImmGen、ALU、IF/ID、ID/EX、EX/MEM、MEM/WB 到工程；添加 `tb_pipeline_cpu_basic.v` 到仿真源。
- Top 设为 `tb_pipeline_cpu_basic`。先跑 `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`；缺失实例必须为空。
- 检查 `MEM_FILE` 默认位置是否与项目实际路径一致。若工程目录不同，修改 Testbench 顶部的 `MEM_FILE` 参数。
- Run Behavioral Simulation → `run all`，观察 FAIL 和最终总结；保存仿真截图及编译顺序，再根据审核流程提交 PR。

## 机器码与期望
详见 A 的 `docs/pipeline_v01_program_map.txt`。`arithmetic_basic.mem` 的 24 行与 A 的正式 `pipeline_v01_arithmetic.mem` 字节序相同。
