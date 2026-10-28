# 五级流水线 CPU 总体架构与接口规范 V0.1

**项目：** LoongArch-Pipeline-CPU  
**版本：** V0.1（双方讨论稿，尚未冻结接口）  
**设计基础：** 已通过功能测试的 27 条指令单周期 CPU  
**开发环境：** Vivado 2019.1，EGO1 FPGA

## 1. 设计目标

在保留现有单周期 CPU 稳定版本的基础上，构建 IF、ID、EX、MEM、WB 五级流水线。

优先保证 27 条指令执行正确，再实现数据前递、流水线暂停、分支冲刷和 I-Cache 集成，最后进行整机性能评估。

## 2. 五个流水线阶段

| 阶段 | 英文名称 | 主要工作 |
|---|---|---|
| IF | Instruction Fetch | 根据 PC 请求指令 |
| ID | Instruction Decode | 译码、读取寄存器、生成控制信号 |
| EX | Execute | ALU 运算、比较分支、计算跳转目标 |
| MEM | Memory Access | 执行 LD.W、ST.W 访存 |
| WB | Write Back | 将结果写回 RegFile |

暂定分支条件与目标地址在 EX 阶段计算。

## 3. 四组流水线寄存器

### 3.1 IF/ID

已实现文件：`rtl/common/if_id_reg.v`

保存 `valid`、PC、32 位指令。

支持 Reset、Flush、Stall，优先级为 Reset > Flush > Stall。

### 3.2 ID/EX

暂定保存：

`valid`、PC、PC+4、指令、rs1/rs2 寄存器地址、目的寄存器地址、rs1/rs2 操作数、立即数、rs1_used、rs2_used、ALU 操作码、立即数选择控制、分支类型、寄存器写使能、存储器读写控制、写回来源选择。

### 3.3 EX/MEM

暂定保存：

`valid`、ALU 结果、ST.W 存储数据、目的寄存器地址、PC+4、访存控制、寄存器写使能和写回选择控制。

### 3.4 MEM/WB

暂定保存：

`valid`、最终写回数据、目的寄存器地址、寄存器写使能。

各阶段可额外保留 PC、指令等调试信息。

## 4. 写回控制规范

保持现有 Decoder 编码：

| wb_sel | 数据来源 |
|---|---|
| 00 | ALU |
| 01 | DMEM |
| 10 | PC+4 |
| 11 | 保留 |

BL 写回 r1；JIRL 写回 rd。无效流水线指令不能产生寄存器或存储器写入。

## 5. IF–I-Cache 接口（建议）

采用单未完成请求、阻塞式 I-Cache。

| 信号 | 方向 | 含义 |
|---|---|---|
| req_valid | IF → Cache Adapter | 请求有效 |
| req_addr[31:0] | IF → Cache Adapter | 请求 PC |
| req_ready | Cache Adapter → IF | 可以接受请求 |
| fetch_valid | Cache Adapter → IF | 响应有效 |
| fetch_inst[31:0] | Cache Adapter → IF | 返回指令 |
| fetch_pc[31:0] | Cache Adapter → IF | 返回指令对应的 PC |
| resp_ready | IF → Cache Adapter | 可以消费响应 |

请求在 `req_valid && req_ready` 时被接受。

响应在 `fetch_valid && resp_ready` 时被消费。消费不代表一定送入 IF/ID：错误路径的响应必须丢弃。

响应在尚未被消费且未被取消前，应保持有效及数据稳定。请求等待接受期间，地址也应保持稳定。

## 6. Stall、Flush 和 Redirect 原则

**Reset：** 清空流水线有效位，停止产生新的有效执行结果。

**Stall：** 当下一级无法接收数据时，相关上游流水级保持状态，不得重复写回或丢失指令。

**Load-use：** 紧跟 LD.W 并需要使用其结果的指令，必要时插入气泡，等待数据可用。

**Forwarding：** EX 阶段优先使用较新的 EX/MEM 结果，其次使用 MEM/WB 结果；仅对数据已经可用的指令进行前递。

**Redirect：** 有效分支在 EX 阶段确定跳转后，取消错误路径的年轻指令，更新取指目标。

**Flush：** 清除相应流水级的 valid，阻止错误路径指令产生副作用。

**Cache Miss 期间 Redirect：** 旧请求允许完成回填，但旧路径响应不得进入 IF/ID；必须保证新目标请求最终能够被接受。

注意：Redirect、流水线反压和 Cache Miss 同时出现时，具体的 PC 更新及事务取消规则仍需双方共同确定，不能仅用一条全局优先级表达所有情况。

## 7. 时钟与复位

统一使用 `clk` 上升沿。

暂定 `rst` 为同步高有效，与现有 `pc_reg.v` 和 `if_id_reg.v` 一致。

## 8. 后续开发分工

**队员 A：** 流水线寄存器、Forwarding、Load-use Stall、分支 Flush、PC 更新及流水线控制。

**队员 B：** I-Cache、IF–I-Cache Adapter、Cache Miss 处理、旧响应失效处理及相关测试。

**双方共同：** 接口确认、流水线 CPU 整合、27 条指令回归、性能与时序验证。

## 9. 需要双方最终确认的事项

- 四组流水线寄存器的正式端口名称、位宽及有效位更新规则。
- EX 阶段分支重定向与下游停顿同时发生时的处理。
- Cache 响应是否需要额外的请求编号或代际标记。
- Cache Miss、数据存储器等待及流水线全局反压的连接方式。
- IF/ID 与 Cache Adapter 之间的响应暂存和接收条件。

**当前状态：V0.1 讨论稿。双方确认后再发布正式 V1.0 接口。**
