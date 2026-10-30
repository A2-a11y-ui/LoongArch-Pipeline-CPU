# V0.5 独立回归：I-Cache 响应保持与 Load-use 形态 Stall 交互

## 1. 为什么不能直接要求自然 Load-use 命中

正式 V0.5 使用的 `icache_if_adapter` 是单 outstanding 状态机：
`ST_IDLE -> ST_WAIT -> ST_RESP -> ST_IDLE`。即使 Cache Hit，也要先接受请求、再产生响应、再完成响应握手；因此命中路径也不能每周期交付一条指令。

CPU 的 IF/ID 在没有新 `if_valid` 时会清除 `id_valid`。这会在相邻指令之间形成流水线气泡，原始 V0.5 程序的 `load_use_stalls=0` 与当前接口吞吐是相符的。仅把机器码改成相邻 `LD.W -> dependent instruction`，不保证自然触发 Load-use。

因此，本测试不伪造“自然 Load-use 已命中”。真实 Load-use 检测继续由已有 V0.3/V0.4 高速 IF 独立回归负责；本测试用 Testbench 对 V0.4 CPU 的 interlock 请求线做两次**明确标注的强制注入**，专门验证 V0.5 Adapter 在 CPU 暂停接收时能否保持完整响应。

## 2. 验证内容

- 8 条真实 LoongArch 机器码，经 V0.5 的 PC/IF、I-Cache、Adapter、V0.4 五级流水线执行；
- 两个 16-byte Cache Line，预期至少 2 Miss、6 Hit、8 refill words；
- WB 6 笔、Store 2 笔，逐笔核对 PC / rd / data 与 PC / address / data；
- `if_delivery_allow` 注入下游暂停，检查 Adapter 的响应 PC / instruction 保持稳定；
- 在 PC `0x1008` 和 `0x1014` 的响应等待期间，各强制注入 2 个周期的 interlock：
  - `hold_if_req=1`
  - `hold_ifid_req=1`
  - `bubble_idex_req=1`
- 检查 `if_valid` 保持、`if_ready=0`、`if_resp_hold=1`、不发生 `if_resp_fire`；
- 检查 IF/ID 记录保持、ID/EX 变 Bubble；若注入前 EX 有效，则检查该指令正常前进到 MEM；
- 释放强制 interlock 后，原响应按原 PC / instruction 被接受一次，不丢失、不重复。

**注意：** 这两次 Stall 是测试注入，不是 CPU 自然检测到的 Load-use。Testbench 另行打印 `natural_load_use_cycles`，如为 0，应按上面的单 outstanding 吞吐边界解释，不能写成自然 Load-use 覆盖已通过。

## 3. 预期架构结果

### WB

| PC | rd | data |
|---|---:|---:|
| 0x1000 | r1 | 0x00000000 |
| 0x1004 | r2 | 0x00000007 |
| 0x1008 | r3 | 0x0000000A |
| 0x1010 | r4 | 0x0000000A |
| 0x1014 | r5 | 0x00000014 |
| 0x1018 | r6 | 0x00000015 |

### Store

| PC | address | data |
|---|---:|---:|
| 0x100C | 0x00000004 | 0x0000000A |
| 0x101C | 0x00000008 | 0x00000015 |

测试前将 `DMEM[0]=7`，其余置零。结束时应有 `DMEM[1]=10`、`DMEM[2]=21`。

## 4. 通过条件

- `ALL TESTS PASSED (V0.5 independent I-Cache/interlock response hold)`
- `TOTAL ERRORS = 0`
- IF：8 条交付、8 个请求、8 个响应、无 outstanding request；
- WB：6/6；Store：2/2；
- 强制 interlock：2 次事件、共 4 个周期、4 个响应保持周期；
- Cache：至少 2 Miss、至少 6 Hit、8 refill words、8 backing transactions；
- 最终 DMEM 数据正确；
- 无 fetch error、无 unsupported、无意外 branch。

## 5. Vivado 2019.1 操作

1. 将 `feature/pipeline-cpu-integration` 合并到 `feature/pipeline-v05-icache-verification`，确认本地包含 Commit `5524b49`。
2. 放置文件：
   - `tb/pipeline_cpu/tb_pipeline_cpu_v05_loaduse.v`
   - `tb/pipeline_cpu/programs/v05_loaduse.mem`
3. 将 Testbench 加入 `sim_1`，设置 Simulation Top 为 `tb_pipeline_cpu_v05_loaduse`。
4. 修改 Testbench 的 `MEM_FILE` 默认绝对路径，或通过 `MEM_FILE` plusarg 指定。
5. 源文件必须包含 V0.5 top、V0.4 CPU、PC/IF Controller、Pipeline Control、Adapter、I-Cache、IMEM、Decoder、ImmGen、RegFile、ALU、Forwarding、Load-use、流水线寄存器和 DMEM。
6. **`icache_if_adapter.v` 只能编译一份。** A 的 V0.5 编译记录使用 `reference_optional/icache_if_adapter.v`；仓库中的 `rtl/memory_cache/icache_if_adapter.v` 与其 Blob SHA 相同（`64bd46802e2abc233d85281288506be3a5739b87`）。若项目已有 `rtl/memory_cache` 版本，不要再添加 optional 副本。
7. Run Behavioral Simulation，执行 `run all`，保存 Tcl Console 完整结果和波形截图。
8. 运行 `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`，保存真实编译顺序。

## 6. 验证边界

本测试验证的是：真实 V0.5 Cache/Adapter/CPU 数据通路，加上 Testbench 注入的 interlock 对响应保持的影响。它不替代：
- V0.3/V0.4 中对真实 Load-use Hazard Detector 的独立回归；
- A 的原始 V0.5 62 字程序回归；
- 未来对多 outstanding / pipelined hit response Adapter 的验证。

若希望 V0.5 自然产生 Load-use Stall，需要先改变 IF 取指吞吐架构（例如支持 hit path 每周期接受/返回指令，或增加预取/响应队列），不能只靠更换机器码保证发生。
