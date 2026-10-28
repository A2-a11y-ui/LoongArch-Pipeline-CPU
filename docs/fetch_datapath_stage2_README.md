# 第二阶段取指与数据通路联合仿真（不依赖 PC 模块）

## 为什么先做这一步

队员 A 正在实现 `pc_reg.v`，本阶段**不新建 PC 寄存器**，而是在 Testbench 中直接提供 `pc`，从而先确认 `imem -> decoder -> regfile/imm_gen -> ALU -> dmem -> regfile` 的基础连线与连续指令执行正确。

### 所需已有模块

| 模块 | 来源 |
|---|---|
| `imem` | `rtl/memory_cache/imem.v`，队员 B，20 项独立测试通过 |
| `datapath_stage1` | `rtl/common/datapath_stage1.v`，51 项集成测试通过 |
| `decoder` | `rtl/common/decoder.v`，目前 13 条指令版本 |
| `imm_gen` | `rtl/memory_cache/imm_gen.v` |
| `alu` | `rtl/alu_branch/alu.v` |
| `regfile` | 队员 A 正式版本；不要同时加入参考模型 |
| `dmem` | `rtl/memory_cache/dmem.v` |

### 本次两个新文件的位置

- `rtl/common/fetch_datapath_stage2.v`：加入 **Design Sources**
- `tb/tb_fetch_datapath_stage2.v`：加入 **Simulation Sources**

### Vivado 2019.1 操作

1. 保持当前 Git 分支为 `feature/memory`；确认此前 51 项测试通过的文件未被覆盖。
2. 把上面两个文件分别保存到指定位置。
3. `Add Sources` → `Add or Create Design Sources` → 添加 `rtl/common/fetch_datapath_stage2.v`。
4. `Add Sources` → `Add or Create Simulation Sources` → 添加 `tb/tb_fetch_datapath_stage2.v`。
5. 确认 `imem.v`、`datapath_stage1.v` 等已有模块都在工程中，且只有一个 `regfile` 定义。
6. 将 `tb_fetch_datapath_stage2` 设置为仿真顶层。
7. `Run Simulation` → `Run Behavioral Simulation`。
8. 在 Tcl Console 中寻找 `Total errors = 0`、`ALL TESTS PASSED`。遇到报错请优先找 `xvlog.log` 中的第一条具体错误。

## 这次验证什么

- ROM 取出的 32 位机器码被解码并执行。
- 16 条连续的基础指令按字节地址 `0, 4, 8 ... 60` 依次执行。
- 既有 ALU 运算，也有有符号移位、立即数和相邻指令依赖。
- `ST.W` 使用 `rd` 字段作为待存数据寄存器；`LD.W` 能读回值。
- 对 `r0` 的写入无效。
- 对未支持指令、未对齐或越界 PC，不产生寄存器/存储器写副作用。
- `exec_en=0` 时写操作关闭。

注意：这不是五级流水线或完整处理器。本 Testbench 的 PC 是人工推动的，每条指令独占一个周期；**不能据此断言已经解决流水线数据冒险**。

## 如何与队员 A 的 `pc_reg.v` 衔接

约定接口：`clk`、`rst`、`pc_en`、`next_pc[31:0]`、`pc[31:0]`。待正式版本合并并独立测试后，下一轮新建 `fetch_unit` 或 CPU 顶层，把 `pc_reg.pc` 接到当前 `fetch_datapath_stage2.pc`；外部负责实现 `next_pc=pc+4`、停顿保持及后续分支重定向。**不要直接修改或覆盖队员 A 的 `pc_reg.v`。**

## 已知边界 / 后续改进

- `imem` 为 256×32 位组合读模型，适合初期仿真；实际 FPGA BRAM/Cache 时序需重新设计。
- `dmem` 为同步写、组合读的教学模型，尚无总线握手或内存异常。
- 当前 `decoder` 只支持队员 B 的 13 条指令，尚未加入队员 A 的全部算术/分支指令。
- `regfile` 读写同址的流水线旁路与 load-use 冒险需要在后续五级流水线实现。
- 测试平台使用 `dut.u_imem.mem[n]` 和 `dut.u_datapath.u_regfile.regs[n]` 层次引用，**仅用于仿真，不可综合上板**。
