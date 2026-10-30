V0.6 Redirect + I-Cache Outstanding + Downstream Stall — 使用说明

包内实际新增：
  tb/pipeline_cpu/tb_pipeline_cpu_v06_redirect_cache_stall.v
  tb/pipeline_cpu/programs/v06_redirect_cache_stall.mem
  docs/pipeline_cpu/v06_redirect_cache_stall_program_map.csv
  docs/pipeline_cpu/v06_redirect_cache_stall_testplan.md

保存 Vivado 成功截图后新增：
  docs/pipeline_cpu/evidence/v06_redirect_cache_stall_pass.png

一、GitHub Desktop
  1. 在 feature/pipeline-cpu-integration 分支执行 Fetch origin / Pull origin。
  2. 确认其基准包含团队指定 Commit 04db474（基准以 GitHub 实际记录为准）。
  3. 创建新分支 feature/pipeline-v06-redirect-cache-stall。
  4. 将此包目录内文件复制进仓库，切勿覆盖已有稳定 RTL。

二、Vivado 2019.1
  1. Add Sources > Add or create simulation sources：新增 tb_pipeline_cpu_v06_redirect_cache_stall.v。
  2. 原有的 pipeline_cpu_core_v05.v / pipeline_cpu_core_v04.v / pc_if_controller.v /
     icache_if_adapter.v / icache_2way_latency.v / imem_latency.v / Decoder 等正式
     Design Sources 继续保留，不要添加重复副本。
  3. 设置 tb_pipeline_cpu_v06_redirect_cache_stall 为 Simulation Top。
  4. Run Behavioral Simulation；Tcl Console 运行 run all。
  5. 默认 ROM 路径：
     D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v06_redirect_cache_stall.mem
     如工程在其他位置，可设置仿真 plusarg +MEM_FILE=路径。
  6. 记录两个 SCENARIO 结果、errors、ALL TESTS PASSED，并截图保存至 evidence 路径。

三、两个场景的性质
  A 真正执行 BEQ：0x100C = 16-byte Cache Line 的最后一条，未完成旧路径 Miss 导致 Drain。
  B 强制协议注入 Redirect：旧路径响应 ST_RESP 被 if_delivery_allow=0 保持之后，
    Testbench force/release Redirect 来验证优先级。B 不代表天然程序形成了这种
    三重并发，也不代表自然 Load-use Hazard 被覆盖。

四、测试统计是预期而不是已经验证的事实
  场景 A：预期 WB=5/5，Store=2/2，自然 Redirect 1 次。
  场景 B：预期 WB=3/3，Store=2/2，注入 Redirect 1 次。
  两场景目标均为 0x1020；错误路径 WB/Store=0。
  该包尚未在 Vivado 2019.1 实际运行，不能直接提交成功截图或宣称 PASS。

五、如仿真失败
  优先保留最早 FAIL 行、完整 Tcl Console、波形和编译顺序；正式 RTL 不要改。
  可把失败截图及 tb 文件发给 ChatGPT 进行定向修订。
