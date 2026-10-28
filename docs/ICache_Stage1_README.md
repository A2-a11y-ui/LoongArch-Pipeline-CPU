# LoongArch-Pipeline-CPU — I-Cache 独立开发 V0.1

本阶段只实现 **独立可测的直接映射指令 Cache**，不覆盖现有 `imem.v`，也不修改已通过 872 项专项验证的 `cpu_top.v`。该代码是后续五级流水线 IF 级的候选部件，**尚未在用户的 Vivado 中实际测试**。

## 1. 设计参数

| 项目 | V0.1 配置 |
|---|---|
| Cache 类型 | 直接映射、只读指令 Cache |
| 数据容量 | 16 行 × 4 字/行 × 4 字节/字 = 256 字节 |
| 每行大小 | 16 字节（4 条 32 位指令） |
| 地址 | 32 位字节地址，4 字节对齐 |
| 拆分 | Tag `[31:8]`、Index `[7:4]`、Word `[3:2]`、Byte `[1:0]` |
| 后备存储器 | 现有 1 KiB `imem.v`，组合读取 |
| 命中 | 组合输出 `inst`、`ready=1`，无需额外等待周期 |
| 缺失 | `ready=0`、`stall=1`，按字回填 4 个时钟边沿 |
| 写策略 | 指令 Cache 只读；不处理指令写入或自修改代码 |
| 计数器 | `hit_count`、`miss_count`、`refill_words` |

## 2. 重要协议

- 上游将 **当前 PC** 连接 `req_addr`，取指请求有效时 `req_valid=1`。
- **只要 `stall=1`，上游必须保持 `req_valid=1` 和 `req_addr` 不变。** 此时 `pc_en=0` 且架构状态不能更新。
- 只有 `ready=1 && fetch_valid=1` 时，当前 PC 的 `inst` 才能被送入 Decoder 并执行；`ready=1 && fetch_valid=0` 表示取指地址非法。
- 在停顿期间禁止寄存器堆写入及 DMEM 写入，避免一条指令重复执行。
- 命中时 `inst` 组合可见；缺失时将依次读出包含该地址的四个字，**整个行写满才置 valid**。
- 当前缺失处理不可取消：若未来分支重定向发生在回填期间，需要由 IF 控制器处理取消请求/丢弃响应。**本版本仅要求缺失期间地址保持**。
- 当前 `mem_addr_valid` 由后备 `imem.v` 返回，只有合法地址才触发回填；测试程序覆盖最大合法地址 `0x3FC` 与非法地址。
- `hit_count`、`miss_count` 是按请求计数：一次缺失回填成功后第一次返回的数据不再作为额外的命中重复计数。

### CPU 后续接线示例（说明用，不是可直接替换的顶层源码）

```verilog
// PC / IF request 由未来的控制器提供：
// req_addr = pc;
// req_valid = step_en;
// icache_stall = stall;
// execute_enable = step_en && !rst && ready && fetch_valid;
// pc_en = step_en && ready;   // 在分支跳转/Flush 时需要另加优先级
// imem.addr = icache.mem_addr;
// decoder.inst = icache.inst;
```

> 不要立即把这一示意替换进目前的 `cpu_top.v`；它还不是五级流水线 IF/ID 握手协议。同步命中的 Cache 会增加路径组合延迟，性能也不能仅凭命中率证明改善。

## 3. Vivado 2019.1 操作（从零开始）

1. 在 GitHub Desktop 中先更新本地 `main`。**不要直接在 `main` 上开发**；建议从最新 main 创建 `feature/icache`，让队员 A 并行开发正式 Decoder。
2. 把 `rtl/memory_cache/icache.v` 复制到仓库同名目录；把 `tb/tb_icache.v` 复制到 `tb`；文档放 `docs`。
3. 打开 `build/loongarch_cpu/loongarch_cpu.xpr`。
4. `Add Sources` → `Add or Create Design Sources`，加入 `rtl/memory_cache/icache.v`；确认旧 `rtl/memory_cache/imem.v` 仍在 Design Sources。
5. `Add Sources` → `Add or Create Simulation Sources`，加入 `tb/tb_icache.v`。
6. 右键 `tb_icache` → `Set as Top`。
7. `Run Simulation` → `Run Behavioral Simulation`。
8. 在 Tcl Console 中确认 `Total errors = 0` 与 `ALL TESTS PASSED`；并截取含 Hit/Miss/Refill 计数器的最终输出及波形截图。
9. 若失败，请提供 Tcl Console 中**第一条 FAIL/ERROR**（不是后续汇总报错）及波形。不要改原始 IMEM/CPU。

## 4. 验收覆盖

- 冷启动首次取指必然 Miss。
- 同一行内 `PC+4`、`PC+8`、`PC+12` 命中。
- `0x0` 与 `0x100` 地址 Tag 不同、Index 相同，发生冲突缺失。
- 相邻行、末尾 `0x3FC`，以及错误地址 `0x400`、`0x3`、`0xFFFFFFFC`。
- 缺失回填时 `stall=1`，只读 4 个字；命中时不回填。
- Hit/Miss/Refill 计数器、Reset 清除及缓存失效。

## 5. 性能评估方式（后续任务）

目前 `imem.v` 为理想组合 ROM，单周期取指不产生等待。**不能与它直接比较并声称 I-Cache 加速了 CPU。**

后续建议给“无 Cache 的后备取指”和“I-Cache 缺失回填”配置一致的多周期后备存储器延迟，使用同一段指令访存序列，比较：

- `hit_rate = hits/(hits+misses)`；
- `miss_rate = misses/(hits+misses)`；
- `total_stall_cycles`、每条指令平均停顿周期；
- 在相同的后备存储器延迟、相同程序、相同频率假设下计算有效 CPI 与加速比；
- 在 EGO1 上做综合之后，再比较 LUT、FF、BRAM 及最高时钟频率。

> 本 V0.1 是行为型直接映射缓存；分布式数组/组合输出可能无法直接推断 BRAM。后续应根据 FPGA 资源、时序报告考虑同步 RAM/BRAM 和流水线协议。

## 6. 给队员 A 的接口沟通

我这边正在 `feature/icache` 独立开发 16 行×4 字的直接映射 I-Cache。接口为 `req_valid/req_addr`、`inst/ready/fetch_valid/stall`，下游复用 IMEM 的 `addr/inst/addr_valid` 作为回填数据源。Cache Miss 时要求 PC 保持、关闭寄存器和数据存储器写入。请先保留现有正式 Decoder 以及 cpu_top 的接口，待五级流水线 IF 级协议确定后我们共同整合 Cache。后续性能评价必须与相同延迟的无 Cache 后备存储器比较。
