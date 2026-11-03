# V0.8 Integrated MDU Stress Regression

## Status

Test candidate generated for `feature/pipeline-v08-cpu-verification`.
**Not yet compiled or simulated in Vivado 2019.1.** All expected values and
counts below are testbench expectations, not measured results.

## Files

- `tb/pipeline_cpu/tb_pipeline_cpu_v08_mdu_stress.v`
- `tb/pipeline_cpu/programs/v08_mdu_stress.mem`
- `docs/pipeline_cpu/v08_mdu_stress_testplan.md`

No RTL is changed. Reuse the existing V0.8 CPU top, datapath, MDU decoder,
`mdu_iterative.v`, I-Cache, and `dmem_latency.v`.

## Coverage

1. All seven MDU opcodes: MUL.W, MULH.W, MULH.WU, DIV.W, DIV.WU, MOD.W, MOD.WU.
2. Back-to-back MDU instructions.
3. MDU-to-ALU forwarding.
4. MDU-to-Store payload forwarding.
5. MDU-to-Branch operand forwarding (MOD.WU result feeds BEQ).
6. Load-use interlocks before MDU and ALU consumers.
7. An MDU instruction remains resident in EX while an older Store occupies
   multi-cycle MEM; the MDU must not start until `mem_stall` clears.
8. I-Cache response remains held while the selected MDU is busy.
9. A completed MDU result is held for four cycles under injected MEM
   backpressure, then transferred exactly once.
10. Taken BEQ flushes a wrong-path MDU at PC `0x106c` and Store at `0x1070`.

## Important RTL boundary

The existing V0.8 RTL defines:

`mdu_start_fire = ... && !mem_stall`

Therefore the MDU cannot naturally begin iterative execution while a real
DMEM request is pending. The test deliberately verifies the real behavior:
the younger MDU waits in EX behind an older Store, then starts after the
Store response. Separately, the testbench forces `dut.u_cpu.mem_stall` only
after the selected MDU has asserted Done and EX/MEM is empty. This injected
hold checks Done/result stability and the later `result_ready` handshake.
It does **not** claim simultaneous MDU Busy with a real DMEM transaction.

## Program map

- `0x1000`–`0x1004`: initialize r1=7 and r2=3.
- `0x1008`–`0x1030`: MDU arithmetic, dependent ALU operations, Stores/Loads,
  and consecutive MDU operations.
- `0x1040`–`0x105c`: Load-use, MDU-to-Store, MDU waiting behind an older
  multi-cycle Store, MDU-to-ALU, and Store/Load checks.
- `0x1060`–`0x1070`: Load-to-MDU, MDU-to-BEQ, wrong-path MDU and Store.
- `0x1074`–`0x10a0`: target-path Store/Load, multiplication, signed
  MULH/DIV/MOD edge values, and final Load-to-ALU dependency.
- `0x10a4`: unsupported sentinel; exactly one unsupported instruction is expected.

## Expected architectural scoreboard

- WB: 31 ordered commits.
- Store: 7 ordered commits.
- MDU: 13 starts, 13 Done events, 13 result transfers.
- DMEM: 14 accepted requests and 14 consumed responses.
- Branch: exactly one taken redirect to `0x1074`.
- Unsupported sentinel: exactly one.
- Wrong-path MDU start at `0x106c`: zero.
- Wrong-path Store commit at `0x1070`: zero.
- Errors/faults: zero.

Final DMEM word values (word indices 0..6):

| Word index | Byte address | Expected value |
|---:|---:|---:|
| 0 | `0x00` | `0x00000015` |
| 1 | `0x04` | `0x00000007` |
| 2 | `0x08` | `0x00000002` |
| 3 | `0x0c` | `0x00000027` |
| 4 | `0x10` | `0x00000006` |
| 5 | `0x14` | `0x00000063` |
| 6 | `0x18` | `0xffffffff` |

Coverage assertions also require:
- at least four Load-use interlock events;
- at least one cycle of MDU-in-EX wait behind the older Store;
- at least four cycles of pending MDU Done under injected backpressure;
- at least one held I-Cache response while MDU Busy;
- nonzero MDU Busy, MEM Stall, and IF response hold counts.

## Vivado 2019.1 steps

1. Add `tb_pipeline_cpu_v08_mdu_stress.v` as a **Simulation Source**.
2. Keep the existing V0.8 RTL and dependency sources unchanged.
3. Place `v08_mdu_stress.mem` at the path used by the `MEM_FILE` parameter,
   or edit that parameter if the local repository path differs.
4. Set Simulation Top to `tb_pipeline_cpu_v08_mdu_stress`.
5. Run `update_compile_order -fileset sim_1`.
6. Run `run all`.
7. Check the exact WB/Store/MDU/DMEM scoreboards and final memory values.
8. Run `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`;
   `Missing instances` must be empty.
9. Save screenshots and logs only after the real Vivado run passes.

Expected success line (not a claimed result):

`ALL TESTS PASSED (V0.8 integrated MDU stress regression)`
