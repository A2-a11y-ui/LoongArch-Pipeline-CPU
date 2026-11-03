# V0.7 DMEM 错误响应整机边界回归测试计划

> 状态：**候选测试，尚未在用户 Vivado 2019.1 环境执行。** 本包中的计数均为设计预期，不能替代 Vivado 实测证据。

## 一、目的与被测系统

本测试针对**整个五级流水线 CPU** 的数据访存错误处理，而不只是 `dmem_latency.v` 单元测试。
被测顶层为已经通过基础测试的 `pipeline_cpu_core_v07_mem.v`，同时复用原版 `pipeline_cpu_core_v07_mem_datapath.v`、I-Cache/Adapter 和正式 `dmem_latency.v`。

**不修改正式 RTL，也不覆盖旧 V0.7 基础/压力/Reset-Abort Testbench。**

V0.7 尚无精确异常入口。本次仅验证 `resp_error` 在响应握手时生成 `mem_fault_valid`，并抑制错误访存的架构副作用；不要求进入异常处理程序。

## 二、错误产生方式

采用真实 32 位 LoongArch 机器码发起 `LD.W` / `ST.W`，**不使用 `force` 人为改写 DMEM 的 `resp_error`**。

测试配置 `DMEM_WORDS=8`，有效字节地址范围 `0..31`，且必须 4 字节对齐。`0x02` 与 `0x06` 非对齐，`0x40` 越界。

| 故障类型 | PC | 访存字节地址 | 预期副作用 |
|---|---|---|---|
| 非对齐 Load | `0x100c` | `0x02` | `mem_fault_valid=1`，不更新 r3（保留 55） |
| 越界 Load | `0x1014` | `0x40` | `mem_fault_valid=1`，不更新 r4（保留 66） |
| 非对齐 Store | `0x1018` | `0x06` | `mem_fault_valid=1`，不写 RAM |
| 越界 Store | `0x101c` | `0x40` | `mem_fault_valid=1`，不写 RAM |

此外包含两次有效 Store、两次有效 Load、两次 Load 结果依赖、一次成立分支及错误路径 Store/WB 屏蔽。

## 三、验收条件

1. **DMEM 事务**：共 8 次有效请求握手、8 次响应握手，无重叠未完成事务，无重复请求或幽灵响应。
2. **错误响应**：共 4 次故障事件，其中错误 Load 2 次、错误 Store 2 次；`mem_fault_valid` 与 `dmem_resp_fire && dmem_resp_error` 同时出现，PC/地址/读写属性严格核对，故障仅对应一次响应。
3. **WB**：10 次成功写回，逐笔比较 PC、rd、data；出错 Load 不写回，分支错误路径不写回。r3 保留 55，r4 保留 66。
4. **Store**：仅 2 次有效 Store 提交，逐笔比较 PC、地址、数据；出错 Store 与错误路径 Store 不得产生提交。
5. **RAM 内容**：`mem[1]=10, mem[2]=11`，其他 `mem[0],mem[3..7]=0`，错误写入不得改变内存。
6. **Branch**：1 次 Redirect，目标 `0x1040`，随后允许继续正常执行。
7. **Backpressure**：MEM Stall 实际发生，且 Stall 中 IF Ready 不得为 1。
8. **结束条件**：设定 4000 周期 watchdog；末尾连续等待 90 周期检查无额外提交；`ERRORS=0`，输出 `ALL TESTS PASSED`。失败使用 `$fatal(1,...)`。

**注意**：正常 WB 与错误响应可能来自不同在途指令，不能禁止同一时钟周期出现任何 WB；只禁止错误 PC 的 WB 和故障 Store 的提交。

## 四、预期检查结果（不是实际结果）

```text
WB=10/10 STORE=2/2 FAULT=4/4
LOAD_ERROR=2 STORE_ERROR=2
REQ=8/8 RESP=8/8 BR=1
STALL>0 ERRORS=0
ALL TESTS PASSED (V0.7 multi-cycle DMEM error response CPU regression)
```

不预先指定仿真结束 ns 数，因为 I-Cache 与 DMEM 延迟将由实际仿真决定。

## 五、Vivado 2019.1 设置

1. 从包含 V0.7 正式 RTL 的最新集成分支创建独立测试分支，例如 `test/v07-mem-fault-regression`。
2. 按目录复制本包里的 **3 个新增文件**（1 个 Verilog TB、1 个 `.mem`、1 个程序映射 CSV）和 1 份测试计划 Markdown。
3. `tb_pipeline_cpu_v07_mem_fault.v` 仅作为 **Simulation Sources** 加入；既有 V0.7 所需 Design Sources 全部保持不变。
4. `MEM_FILE` 默认为 `D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v07_mem_fault_basic.mem`；如你的工程路径不同，修改 TB 这个参数，不要修改正式 RTL。
5. 将 `tb_pipeline_cpu_v07_mem_fault` 设为 Simulation Top。
6. Run Behavioral Simulation 后，在 Tcl Console 输入 `run all`。
7. 再执行 `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`，确认 `Missing instances` 为 `< empty >`。
8. 只有在 Vivado 实际显示 `ALL TESTS PASSED`、`ERRORS=0` 后，才保存 `docs/pipeline_cpu/evidence/v07_mem_fault_pass.png` 和完整 `simulate.log`。

## 六、课设报告可引用的验证方案

- **目标**：验证非对齐及越界 Data Memory 访问的异常状态传播与副作用抑制。
- **方法**：将 DMEM 深度缩小为 8 个 32 位字，用真实机器码制造两个 Load 和两个 Store 故障，另插入合法访存、数据依赖和分支指令。
- **观察信号**：`dmem_req_fire`、`dmem_resp_fire`、`dut.u_cpu.dmem_resp_error`、`mem_fault_valid/pc/addr/store`、`mem_stall`、`wb_commit_*`、`mem_store_commit_*`。
- **判定方法**：握手计数 + 顺序 Scoreboard + 寄存器最终值 + RAM 全部 8 字检查 + watchdog。
- **结果表述**：仅在完成真实仿真后填写实际通过/失败数值；不宣称实现了尚不存在的异常入口、精确异常或完整 Trap 机制。
