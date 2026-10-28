# 第五阶段：LoongArch 分支指令联合集成（单周期功能原型）

## 本包内容

| 文件 | 放置目录 | Vivado 类型 |
|---|---|---|
| `branch_decode_stage5.v` | `rtl/common/` | Design Sources |
| `branch_cpu_stage5.v` | `rtl/common/` | Design Sources |
| `tb_branch_cpu_stage5.v` | `tb/` | Simulation Sources |

**绝对不要覆盖共享的 `rtl/common/decoder.v`。** 本包的 `branch_decode_stage5.v` 是临时增加的五条分支译码器，只用于验证双方模块能够共同工作。之后由 A、B 合作将其逻辑合并进正式 Decoder。

## 依赖：必须使用仓库里的正式模块

- `rtl/alu_branch/branch_unit.v`，队员 A PR #4 合并后的版本
- `rtl/common/pc_reg.v`，队员 A PR #3 合并后的版本
- `rtl/common/regfile.v`，队员 A PR #2 合并后的版本（路径以实际仓库为准）
- `rtl/alu_branch/alu.v`，队员 A PR #1 版本
- `rtl/common/decoder.v`，你已通过 38 项测试的 13 指令版本
- `rtl/common/cpu_defs.vh`
- `rtl/memory_cache/imm_gen.v`，**必须是 V2**（选码 5/6 用于分支）
- `rtl/memory_cache/imem.v`、`rtl/memory_cache/dmem.v`

不要将 `pc_reg_reference.v` 或 `regfile_reference.v` 同正式模块一起加入工程，也不要新增第二个名为 `decoder` 或 `branch_unit` 的模块。

## Vivado 2019.1 步骤

1. GitHub Desktop 中，当前分支 `feature/memory` 的有效修改先 Commit+Push；Fetch/Pull 最新 `main`，再更新到 `feature/memory`。确认正式 PC、Regfile 和 Branch Unit 在本地。
2. 在 Windows 文件资源管理器把三个文件放到上表对应的文件夹；有同名文件时先比较并备份。
3. 打开 `build/loongarch_cpu/loongarch_cpu.xpr`。
4. 使用 `Add Sources → Add or Create Design Sources → Add Files`，添加：
   - `rtl/common/branch_decode_stage5.v`
   - `rtl/common/branch_cpu_stage5.v`
5. 使用 `Add Sources → Add or Create Simulation Sources → Add Files`，添加 `tb/tb_branch_cpu_stage5.v`。
6. 不要重复添加原来已经存在的 `alu.v`、`decoder.v`、`imem.v`、`regfile.v`、`pc_reg.v`、`dmem.v`、`imm_gen.v` 和 `branch_unit.v`。
7. 在 Simulation Sources 右键 `tb_branch_cpu_stage5` → **Set as Top**。
8. 点击 `Run Simulation → Run Behavioral Simulation`，检查 Tcl Console。

## 本轮验证内容

本测试平台在 IMEM 中装载真实机器码，并在时钟边沿逐条执行，覆盖 28 次指令提交：

- BEQ 条件成立与前/后向跳转；BNE 条件成立和不成立及负偏移
- B 正向、负向跳转；BL 目标地址及寄存器 r1=PC+4
- JIRL 正向、负向跳转；JIRL rd=PC+4
- `ST.W` 第二读源来自 rd 字段；`LD.W` 读回；AND 运算
- 跳转跳过应被取消的指令（副作用检查）
- `step_en=0` 的 PC 停顿与写入禁止
- r0 写保护、非法指令无副作用、越界取指无副作用、同步复位优先

注意：Testbench 会以层次路径 `dut.u_imem.mem[...]` 向仿真指令 ROM 写入测试指令，并检查 `dut.u_regfile.regs[...]` 以及 `dut.u_dmem.mem[...]`。这是**仅用于仿真的测试方式**；不等于已生成 FPGA ROM 初始化文件。如果队员 A 改动了内部寄存器数组名 `regs`，需要相应修改测试探针，但**不需要修改 regfile 的公开接口**。

## 预期结果（请以你实际 Vivado 输出为准）

```text
Committed instructions = 28
Total checks = <自动统计的检查次数>
Total errors = 0
ALL TESTS PASSED
```

本包没有在你的 Vivado 环境中运行。若遇编译错误，请提供 `xvlog.log`；若出现 elaborate 错误，请提供 `elaborate.log`；如出现 FAIL，截取第一条 FAIL 和其前后的日志。

## 对接与下一阶段

完成本轮后，将第五阶段测试结果发给队员 A，并共同把 `branch_decode_stage5` 的行为并入正式 `decoder.v`，统一 `branch_type`、源寄存器选择、PC+4 写回选择和 `redirect` 控制。**暂时不要把此 stage5 原型当作最终 CPU 顶层**。之后还要实现流水线寄存器、数据前递、分支冲刷、结构冒险，以及 I-Cache 和量化性能对比。

### 关键指令格式参考

- GNU Binutils `loongarch-opc.c`：https://gnu.googlesource.com/binutils-gdb/+/150bfae1d719a3b5c12edc780f0b360a1056b802/opcodes/loongarch-opc.c
- LoongArch Reference Manual Volume 1：https://loongson.github.io/LoongArch-Documentation/LoongArch-Vol1-EN.html
