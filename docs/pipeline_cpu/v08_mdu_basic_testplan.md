# V0.8 MDU + multi-cycle DMEM + I-Cache integration — test plan

## State

**Generated integration candidate. Not yet compiled or simulated in Vivado 2019.1.**
All expected values below are *predictions*, not results. The existing V0.7 baseline
and teammate's `mdu_iterative.v` are not modified.

## New RTL

- `rtl_test_only/mdu_decode_v08.v`: the seven original LoongArch 3R opcodes mapped to the MDU's internal 3-bit codes; stable `decoder.v` stays unchanged.
- `rtl_test_only/pipeline_cpu_core_v08_mdu_datapath.v`: V0.7 datapath clone with independent MDU EX interlock/result handshake.
- `rtl_test_only/pipeline_cpu_core_v08_mdu.v`: V0.7 fetch/cache wrapper clone with MDU observability.

## Design rules

- `start` fires once when a valid EX MDU has ready forwarding operands and MEM is not stalled.
- EX, ID, IF are held until `done`. Prior MEM/WB entries are allowed to drain; EX/MEM is bubbled when it can advance but MDU cannot.
- With MEM stall, EX/MEM holds, and MDU's `done/result` remain held until the actual EX/MEM acceptance edge.
- `mdu_result_fire = mdu_done && mdu_started && ex_valid && ex_is_mdu && !mem_stall && !ex_operand_wait && !rst`.
- MDU numerical result goes into the existing EX/MEM ALU result data field (wb_sel=ALU) and then standard WB. No duplicate commit.
- Original V0.7 I-Cache adapter / DMEM / branch / forwarding / pipeline registers all remain unchanged.

## TB1: `tb_pipeline_cpu_v08_mdu_basic`

The 29-word LoongArch program covers all seven opcodes and dependent arithmetic,
repeated MDU instructions, signed and unsigned edges, MDU->BEQ dependency, wrong-path
Store/WB suppression, an older LD followed by MDU, and ordinary DMEM Store/Load.

**Expected:** WB=23/23, STORE=2/2, MDU_START=15, MDU_RESULT=15,
BR=1 to PC 0x1044, DMEM_REQ=3, DMEM_RESP=3, wrong path RAM[2]=0,
RAM[1]=7, RAM[3]=8, errors=0.

The TB checks exact in-order WB PC, rd and data and Store PC/address/data,
no extra commits, no spurious faults, no IF acceptance while either MEM or
MDU stalled, no overlapping DMEM requests, held MDU result stability, and a
6000-cycle timeout. **Testbench output must be actually inspected in Vivado.**

The first CPU test is for core integration, not a proof of every cycle-overlap
scenario. A separate directed datapath test is recommended to force simultaneous
MDU busy and older DMEM stall, as well as held Done while MEM is stalled.

## TB2: `tb_pipeline_cpu_v08_legacy_v07_regression`

The original known-working V0.7 18-word program and its original reference
scoreboard, run through the new V0.8 top; success proves MDU integration did
not regress old arithmetic/branch/load-store functionality.

## Vivado 2019.1

1. Add the new **three RTL files** as Design Sources (or available in Simulation
   sources for this test-only integration project). Keep existing RTL sources,
   especially `rtl/alu_branch/mdu_iterative.v` and V0.7's dependencies.
2. Add the **two new TB files** as Simulation Sources.
3. Select `tb_pipeline_cpu_v08_mdu_basic` as simulation top.
4. Program path in TB is set to `D:/CPU_Project/LoongArch-Pipeline-CPU/tb/pipeline_cpu/programs/v08_mdu_basic.mem`. Adapt if needed.
5. Run `launch_simulation`, `run all`, then check `ALL TESTS PASSED`, counters,
   waveform, and `report_compile_order -of_objects [get_filesets sim_1] -used_in simulation`.
6. Re-select `tb_pipeline_cpu_v08_legacy_v07_regression`, run again and record its output.
7. Save independent evidence and logs only AFTER observed PASS; do not commit simulated claims.

## Compile dependencies

Existing module set: `alu`, `branch_resolve_v04`, `decoder`, `dmem_latency`,
`ex_mem_reg`, `forwarding_unit`, `icache_2way_latency`, `icache_if_adapter`,
`id_ex_reg`, `if_id_reg`, `imem_latency`, `imm_gen`, `load_use_hazard_unit`,
`mem_wb_reg`, `pc_if_controller`, `pipeline_control_unit`, `regfile`,
`mdu_iterative` (plus `cpu_defs.vh`). The V0.8 new files are described above.
Missing instances must be `< empty >`.

## Open verification gaps / limitations

- Explicit MDU Done + MEM Stall overlap is not guaranteed by the basic cache-driven test.
- Exact Reset interruption of an executing MDU and injected downstream stall require extra directed tests.
- Output `mdu_div_zero` is only an observability signal; no architectural trap is implemented.
- This is an educational, bounded-program TEST harness, **not final FPGA timing/board validation**.
