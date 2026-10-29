V0.1 算术流水线联合验证交接说明

1. CPU 顶层：pipeline_cpu_core_v01.v，模块 pipeline_cpu_core_v01；外部输入 if_valid/if_pc/if_inst。
2. 原始 TB：tb_pipeline_cpu_core_v01.v。注意：这个 TB 直接用 Verilog 的 inst_r/inst_i/inst_u 函数生成指令，不使用 $readmemh。
3. 独立机器码测试程序：pipeline_v01_arithmetic.mem。共 24 行，每行一个 32 位十六进制机器码，ROM[0] 对应 PC=0x00001000，ROM[index] 地址=0x1000+4*index。供队友新写 $readmemh TB 使用。
4. 地址/机器码对应表：pipeline_v01_program_map.txt。
5. PC=0x1000..0x1030 为第 1 组（13 条含 5 条不产生写回的输入），PC=0x1034 开始第 2 组（11 条）。必须在发完第 1 组后，通过 if_valid=0 注入至少 6 个空拍，期间不要消耗 ROM 的下一条指令或推进 PC，避免 RAW 数据相关。也可以按正确流水线时序另行安排更多空拍。
6. 注意：unsupported=4 是有意测试的四条输入：0xFFFFFFFF（非法指令）、LD.W、ST.W、B。后三者是 LoongArch 合法类型，但当前算术-only 顶层明确未实现，不应解释为 Decoder 不支持。另有 1 条 ADDI.W r0,r0,77 应合法执行但禁止写回 r0，不计入 unsupported。
7. 原始 TB 期望 commits=19/19, unsupported=4, hazards=0, errors=0。测试用户实际 Vivado 2019.1 截图证据请从 docs/test_results/pipeline_v01_19commits_pass.png 提交；此交接包不包含截图，请保留用户项目中的真实证据。
8. 不修改稳定 CPU27 和 V0.9 RTL；新独立验证继续在 feature/pipeline-cpu-verification 分支上完成。
9. 这个 .mem 文件仅表示原始 TB 的 24 条有效指令（不含六个 if_valid=0 空拍）；不是 Vivado 自动可运行的完整 TB。
