# V0.9 Independent WB / Store Scoreboard — Interface & Contract

Status: Self-test completed in Vivado 2019.1.
Result: 11/11 self-test cases passed, 0 self-test failures.
Simulation finished at 1471 ns.
Expected scoreboard errors in negative test cases are intentional
and are checked by the outer self-test.

**Purpose:** Verify that a CPU emits the correct *architectural side effects*, not merely the correct numerical counts. This monitor is standalone, simulation-only Verilog-2001. No existing V0.1–V0.8 RTL or FPGA top is modified.

## 1. Files

- `tb/pipeline_cpu/v09_commit_scoreboard.v`: reusable independent commit scoreboard.
- `tb/pipeline_cpu/tb_v09_scoreboard_selftest.v`: synthetic event generator and positive/negative self-test.
- `docs/pipeline_cpu/v09_scoreboard_reference.csv`: human-reviewable independent reference transactions for the self-test.
- `docs/pipeline_cpu/v09_scoreboard_contract.md`: this specification.
- `README_V09_Scoreboard_使用说明.txt`: operation instructions.

## 2. Required adapter signals (to be agreed with Team B)

| Checker port | Width | Semantics |
|---|---:|---|
| `clk` | 1 | Clock that samples architectural commit events |
| `sb_rst` | 1 | Synchronous **checker epoch** reset; may be separate from CPU reset |
| `wb_commit_valid` | 1 | **One cycle per actual register write**, not pipeline `valid`; excludes r0 |
| `wb_commit_pc` | 32 | PC of instruction performing this register write |
| `wb_commit_rd` | 5 | Register destination (1–31) |
| `wb_commit_data` | 32 | Actual 32-bit value written to architectural register |
| `store_commit_valid` | 1 | **One cycle per actually committed Store**, not `mem_req_valid` |
| `store_commit_pc` | 32 | PC of instruction performing this Store |
| `store_commit_addr` | 32 | Effective memory address (byte addressing convention must be agreed) |
| `store_commit_data` | 32 | Value actually committed, before or after any byte-lane transform only if documented |
| `check_finish` | 1 | One-cycle final check pulse after expected events and drain/quiet period |
| `wb_count`, `store_count` | 32 | Observed commitment counts |
| `error_count` | 32 | Number of detected violations; multiple same-cycle violations are accumulated |
| `check_done`, `check_pass` | 1 | Final comparison occurred / no detected violation yet |

**Important:** `wb_commit_valid` must **not** mean `wb_valid` held while stalled. If WB is repeated during a stall, a valid pulse on consecutive clock edges represents two writes and the scoreboard should flag that. Likewise, Store is counted when RAM or the observable architectural state is actually updated (in current `dmem_latency` this may be tied to response handshake, not request acceptance). Confirm the final definition against B's RTL.

## 3. Reference programming

The CPU-level Testbench builds golden tables independently, **before releasing `sb_rst`**:

```verilog
u_sb.clear_expectations;
u_sb.expect_wb(32'h00001000, 5'd1, 32'd6);
u_sb.expect_wb(32'h00001004, 5'd2, 32'd3);
u_sb.expect_store(32'h00001010, 32'd4, 32'd18);
```

The order of `expect_wb` calls is the expected order **within WB events**; `expect_store` similarly defines expected Store sequence. The checker compares each real event using case-inequality (`!==`) to reject X/Z values.

Reference data must be derived from a separate instruction/program model and must not be copied from the DUT's own output. The attached reference CSV is **only a synthetic monitor self-test trace**, not a runnable LoongArch instruction program.

### Reset and epochs

`sb_rst` resets the checker's counters, error state and final-pass state; it does **not** clear the golden table. A new test epoch may start after CPU reset, but any already committed memory side effects must be considered in the next epoch's independent reference. Do not use checker reset to hide unintended side effects. The actual CPU reset must be observed and checked separately.

## 4. What the checker flags

- Wrong WB PC / destination register / data.
- Wrong WB ordering and duplicate or extra WB.
- Wrong Store PC / address / data.
- Wrong Store ordering and duplicate or extra Store.
- Missing WB or Store (on `check_finish`).
- An architectural WB to register 0.
- Unknown X/Z on either valid signal or finish signal.
- Side-effect events after final check (while simulation remains active).
- Two independent errors in the same cycle are counted separately.

### Limitations (do not overclaim)

- Two separate reference streams **do not impose a total ordering between WB and Store**. If the CPU exposes a unified retirement/commit stream, add a global-order checker in a later iteration.
- It does not itself check ISA arithmetic, memory data retention, or unobserved internal events. CPU-level programs, memory models and end-state assertions remain necessary.
- It does not prove that an FPGA is physically synthesizable or running correctly on EGO1.
- `check_finish` must be asserted only after the CPU has drained outstanding work; continue to simulate for a quiet observation window to catch late commits.
- After `check_finish`, `check_pass` remains a live indicator that can drop if an extra event occurs. The Testbench must inspect it at the *end* of the observation window.

## 5. Built-in independent self-test cases

| Case | Stimulus | Expected checker result |
|---|---|---|
| 1 | Valid WB/Store stream; simultaneous WB and Store | PASS |
| 2 | Duplicate WB | FAIL detected |
| 3 | Wrong WB data | FAIL detected |
| 4 | Missing Store | FAIL detected |
| 5 | Wrong WB order | FAIL detected |
| 6 | Wrong Store address | FAIL detected |
| 7 | Simultaneous wrong WB and Store values | FAIL detected; at least 2 errors |
| 8 | Correct stream at `check_finish` | PASS |
| 9 | Extra WB **after** final check | FAIL detected |
| 10 | Duplicate Store | FAIL detected |
| 11 | WB destination r0 | FAIL detected |

Negative cases intentionally produce `V09 SB FAIL` diagnostics **inside the checker**. This is expected: the **outer** Testbench passes only if all deliberate faults are detected. Do not interpret an inner `V09 SB FAIL` as a failed self-test.

Expected successful self-test summary (to be confirmed by actual Vivado run):

```
V09 SCOREBOARD SELFTEST RESULT CASES=11 PASS=11 FAIL=0
ALL TESTS PASSED (V0.9 independent WB/Store scoreboard self-test)
```

No numerical result from this candidate file should be presented as a real Vivado result before executing it.

## 6. Later CPU-level integration

After B confirms V0.9 top-level name, reset polarity, commit-port names, instruction memory initialization and Store commitment definition:

1. Instantiate the new CPU top in a fresh `tb_v09_cpu_*.v`.
2. Wire its *real* WB/Store commit outputs (or documented architectural monitoring wrapper) to `v09_commit_scoreboard`.
3. Precompute an independent golden event table for each machine-code program.
4. Run under configured I-Cache miss, DMEM latency, MDU busy, branch and reset combinations.
5. Assert a completion criterion + timeout; drain pending transactions; pulse `check_finish`.
6. Continue a quiet observation window, then require `check_done && check_pass && error_count==0`.
7. Save Testbench, instruction `.mem`, reference table, actual logs, screenshots, compile-order report, and hardware evidence separately.

**Branch policy:** develop in `test/pipeline-v09-verification`, review against `feature/pipeline-cpu-integration`; do not modify stable RTL.
