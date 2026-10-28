# 五级流水线 CPU 总体架构与接口规范 V0.2（双方讨论稿）

**项目：** LoongArch-Pipeline-CPU  
**状态：** 供 PR #10 讨论和 A/B 双方确认；**不是已经冻结的 V1.0，也不是 RTL 联合仿真通过声明**  
**依据：** `pipeline_arch_spec_v0.1.md`（队员 A）、队员 B 的架构审核建议、`icache_if_adapter.v` V0.5.1（队员 B，221 项独立检查通过）、`if_id_reg.v`（队员 A，20 项独立检查通过）

## 1. 总体目标及阶段划分

保留已经通过五组功能回归的 **27 种指令单周期 CPU** 作为对照基线；新建五级流水线顶层，不直接改写稳定单周期顶层。五级：IF（请求/返回指令）、ID（译码/寄存器读取/相关检测）、EX（ALU/分支条件和目标）、MEM（LD.W/ST.W）、WB（写回）。分支暂定在 EX 决策。先实现无 Cache 流水线基本数据通路，再连接 IF Adapter 与两路 LRU Cache。

## 2. 流水线寄存器与有效位

| 寄存器 | 至少保存 | 控制约束 |
|---|---|---|
| IF/ID | `valid, pc, inst` | 同步高有效 `rst`；优先级 **Reset > Flush > Stall > Capture**。当允许推进但没有新响应时写入 `valid=0` 的气泡 |
| ID/EX | `valid, pc, pc_plus4, inst(调试可选), rs1_idx, rs2_idx, dest_idx, rs1_data, rs2_data, rs1_used, rs2_used, imm, alu_op, alu_src_sel, branch_type, reg_we, mem_read, mem_write, wb_sel` | Load-use 时 ID/EX 插入气泡；允许 EX 中旧 Load 向后推进 |
| EX/MEM | `valid, alu_result, store_data, store_src_idx(若需 MEM 前递), dest_idx, pc_plus4, mem_read, mem_write, reg_we, wb_sel` | `ST.W` 的 store_data 必须能从相关指令前递；不得反复提交同一 Store |
| MEM/WB | `valid, wb_data, dest_idx, reg_we, pc(可选调试)` | 写回以 `valid && reg_we && dest_idx != 0` 为准 |

写回选择与现有 Decoder 保持一致：`wb_sel=00` ALU、`01` DMEM、`10` PC+4、`11` 保留。BL 目的寄存器 r1；JIRL 目的寄存器 rd。无效指令不得产生对寄存器堆或 DMEM 的副作用。

## 3. IF–I-Cache Adapter V0.5.1：冻结候选接口（以现有 Verilog 端口为准）

| 方向（相对于 Adapter） | 信号 | 含义 |
|---|---|---|
| 输入 | `clk`, `rst` | 上升沿工作；同步高有效复位 |
| 输入 | `if_req_valid`, `if_req_addr[31:0]` | IF 发起请求及字节地址；等候时保持 `valid=1` 和地址稳定 |
| 输出 | `if_req_ready` | 仅能否**接受新请求**，不是“Cache 数据已到” |
| 输出 | `if_resp_valid`, `if_resp_pc[31:0]`, `if_resp_inst[31:0]`, `if_resp_error` | 结果有效、关联 PC、指令和错误状态 |
| 输入 | `if_resp_ready` | IF 是否有容量**消费响应** |
| 输入 | `redirect` | 同步 Redirect 事件；优先于请求/旧响应，取消错误路径结果 |
| 输出 | `busy` | 状态观察信号，**不等于 IF/ID.stall** |

Adapter 内部已经例化 `icache_2way_latency`，IF 集成层**不要重复例化**另一个 Cache；后备存储器侧端口及调试计数器照现有 RTL 保留。

握手只在 `posedge clk` 成立：

- `req_fire = if_req_valid && if_req_ready`：且在 `rst=0 && redirect=0` 下代表**恰好接受一笔**请求；IF 在接受前必须保持地址和 valid 不变。PC 的顺序推进与已接受请求的关联由 IF 控制模块管理。
- `resp_fire = if_resp_valid && if_resp_ready`：代表**恰好消费一笔**响应；未消费且未取消的响应，其 `valid/pc/inst/error` 必须保持稳定。
- `if_resp_error=1` 不是正常指令（不得向后级发射有效写回/存储操作）；第一版可由测试平台明确终止并报错，若整机引入异常处理须再定义异常控制。
- 单未完成请求、阻塞式响应；原则上等待上一笔响应消费后才能接受下一笔请求。本方案首先保证正确性，不保证 Hit 的一周期连续吞吐。

## 4. IF/ID 背压与 bubble（双方必须按此联合验证）

定义 `id_can_advance` 为下游允许 IF/ID 中旧指令进入 ID/EX 的条件；`ifid_flush` 为本周期失效 IF/ID 的控制。建议的握手关系（行为定义，不是无条件可粘贴的硬件赋值）：

- `if_resp_ready = !rst && !redirect && !ifid_flush && id_can_advance`，并且 **IF/ID 在该时钟沿确实允许接收**；不能在下游保持时悄悄消费响应。
- `ifid_flush=1`：即便 `stall=1`，仍将 IF/ID 的 `valid` 清为 0。若 Redirect 触发，也同时确保 Adapter 旧响应失效。
- `id_can_advance=0`：IF/ID 保持，`if_resp_ready=0`；Adapter 必须维持旧响应不变（若有）。
- `id_can_advance=1 && if_resp_valid=1`：一次响应握手，IF/ID 捕获 `pc/inst/valid=1`（错误响应另行禁止普通有效指令进入）。
- `id_can_advance=1 && if_resp_valid=0`：IF/ID 装入 `valid=0` bubble，避免同一条指令进入 ID 两次。

应在模块组合接口上检查没有 `ready→valid→ready` 组合环。`busy=1` 既可能代表正在等待 Miss，也可能代表响应已就绪但等待被接收；因此不能直接用于全局 PC/IFID Stall。

## 5. Redirect / Flush / Cache Miss

- 分支在 **EX** 且本条有效时决定 Redirect，EX 中分支本身保留并进入后级；**年轻的** IF/ID 与 ID/EX 中错误路径指令必须被清除，而不得错误冲刷已处于 EX 的分支。
- BL/JIRL 的 `PC+4` 沿 EX/MEM、MEM/WB 正确传递并写回。
- **PC 控制器（A）** 对 `redirect_pc` 负责：Redirect 发生当拍保存新目标地址；即使 Cache Adapter 的 `busy=1`，也不能丢目标。之后持续提交目标 PC 请求直到 `req_fire`。
- **Cache Adapter（B）** 仅收到 `redirect`，不接收 `redirect_pc`，也不自行发起新取指。对旧未完成请求：若不能物理取消，则 `DRAIN` 回填直到结束；旧响应绝不可产生有效 IF/ID 更新。
- Redirect 与旧请求、响应同周期冲突时以 Redirect 为准；Redirect 事件需要**恰好一次**生效，采用脉冲/事件寄存或等效去重。旧请求等待期间发生 Redirect 后，不得再驱动旧请求地址。
- 若 Redirect 与下游 Stall 同时发生，Flush/Redirect 控制不能被 Stall 吞掉；各个流水线寄存器的局部优先级仍要单独定义，不能简单建立“全局统一 Stall”。
- 若收到连续 Redirect，须规定最新有效分支优先/串行处置的明确策略并增加专门测试；首版可约束“同一时刻只允许一笔有效 EX Redirect”但必须写明。

## 6. 数据冒险与访存推进

- `rs1_used` / `rs2_used` 由真实指令语义而不是简单看字段非零决定；ST.W 的 store 数据寄存器来自编码 `rd`，BEQ/BNE 同样需要第二比较操作数。
- Forwarding 优先 EX/MEM **已就绪结果**，其次 MEM/WB，排除 `r0`、无效级和不写回指令；对 `LD.W` 不得将尚未读取的数据地址误当作 Load 结果进行前递。
- Load-use 命中：保持 IF/ID 的当前指令，将 ID/EX 设为 bubble，并使前一条 LD.W 继续前进；不可把 EX/MEM/MEM/WB 一起冻结造成死锁。
- ST.W 必须有 store_data 前递，覆盖 `ALU → ST.W` 与 `LD.W → ST.W`，同时覆盖地址计算所依赖的前递。
- 首版可采用组合式 DMEM/固定一周期存储访问假设；将来改为多周期时必须规定 MEM 级请求接受、响应完成及阶段反压，确保 Store 恰好执行一次。

## 7. 时钟与复位

统一 `posedge clk`，`rst` **同步高有效**。复位时，各级 valid 清零、IF 新请求关闭；Adapter 和后备存储器的未完成状态按现有实现复位。独立测试以同一复位行为为前提，不能默认真实外部总线事务可以被立刻取消。

## 8. 双方职责与 V1.0 冻结门槛

- A：IF PC/取指控制、四级流水线寄存器（含 IF/ID）、Forwarding、Load-use、分支 Flush/Redirect、全局级间推进控制；修改本文 V0.2 后形成 V1.0 候选。
- B：维持 Adapter V0.5.1 和 2-Way LRU Cache 的已测实现，负责请求/响应/反压/Redirect 旧事务排空以及取指子系统联合 Testbench。
- 双方：确认本文件所有握手、有效位、Stall/Flush 和 PC 控制；通过 IF/ID+Adapter+I-Cache 独立联合测试后，再将接口标记为 V1.0 并启动大规模依赖接口的 RTL 集成。保留单周期 CPU27 稳定基线，不改原有正式顶层。

### 最小联合验收用例

1. 顺序至少 3 条指令，PC 单调按 4 增长，不漏、不重；无返回时允许 bubble。
2. Cache Miss + ID Stall：响应保持；解除 Stall 后恰好消费一次。
3. 普通 Redirect、Miss 期间 Redirect、Cache 完成沿 Redirect：旧 PC 指令不进入有效 IF/ID，新目标最终到达。
4. Redirect 与 Stall 同时、Flush 与 Stall 同时、Reset + Flush + Stall：有效位正确。
5. Invalid/error 返回不会产生后续副作用。
6. 加载使用冒险、寄存器值前递、Store 数据前递、BL/JIRL 链接地址在未来整机流水线中验证。
7. 与单周期 CPU27 参考的写回/访存提交轨迹对齐，最后再完成 FPGA 板级顶层的 IOB、布局布线与时序验证。

## 9. V0.1 → V0.2 修订摘要

1. 把概念性接口名映射到既有 Adapter 实际端口；补 `if_resp_error`, `redirect`, `busy`。
2. 将请求被接受、响应被消费、IF/ID 实际捕获三者分开定义。
3. 规定空响应 bubble、下游背压时响应保持，不用 `busy` 直接生成 Stall。
4. Redirect 目标 PC 由 A 保存，Adapter 负责旧事务失效、排空；明确 EX 分支不被 Flush。
5. 补充 BL/JIRL、ST.W store-data 前递及 load-use 等细节。
6. 写明仍为**讨论稿**，不得将独立 Cache 测试作为五级流水线联合验证结果。
