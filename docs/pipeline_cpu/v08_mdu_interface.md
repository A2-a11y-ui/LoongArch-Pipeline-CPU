# V0.8 Iterative MDU — module interface and five-stage CPU integration contract

**Project:** LoongArch-Pipeline-CPU  
**Applies to:** `mdu_iterative.v` and the proposed `pipeline_cpu_core_v08_mdu*` CPU integration  
**Target:** LoongArch LA32, Verilog-2001, Vivado 2019.1  
**Status:** MDU module-level regression reported PASS (22 cases, 227 checks, 0 errors); **V0.8 CPU integration and concurrent-stall cases not yet confirmed by Vivado**.  
**Compatibility:** Do not overwrite the V0.7 CPU, stable `decoder.v`, `dmem_latency.v`, I-Cache, V0.9 or CPU27 baseline.

## 1. Architectural instruction encoding (not the 3-bit MDU operation code)

All seven instructions use the *LoongArch 3-register instruction format*:

```
  31                            15 14           10 9             5 4             0
 +--------------------------------+---------------+---------------+---------------+
 |  fixed 17-bit instruction op   |    rk[4:0]    |    rj[4:0]    |    rd[4:0]    |
 +--------------------------------+---------------+---------------+---------------+
```

- `rd = inst[4:0]` (destination register)
- `rj = inst[9:5]` (operand A register)
- `rk = inst[14:10]` (operand B register)
- **Matching mask:** `32'hFFFF8000`
- **Match condition:** `(inst & 32'hFFFF8000) == MATCH_VALUE`
- **Full 32-bit machine word:** `MATCH_VALUE | (rk << 10) | (rj << 5) | rd`
- The fixed match values have their low 15 bits zero; `rd`, `rj`, and `rk` can each range from 0 to 31.

| LA32 instruction | Full instruction match value (`inst & mask`) | 3-bit internal `mdu_op` | Architectural result written to `rd` |
|---|---|---|---|
| `MUL.W` | `32'h001C0000` | `3'b000` | Low 32 bits of signed 32 x 32 product |
| `MULH.W` | `32'h001C8000` | `3'b001` | High 32 bits of signed 32 x 32 product |
| `MULH.WU` | `32'h001D0000` | `3'b010` | High 32 bits of unsigned 32 x 32 product |
| `DIV.W` | `32'h00200000` | `3'b011` | Signed quotient (truncate toward zero) |
| `DIV.WU` | `32'h00210000` | `3'b100` | Unsigned quotient |
| `MOD.W` | `32'h00208000` | `3'b101` | Signed remainder (sign of dividend when nonzero) |
| `MOD.WU` | `32'h00218000` | `3'b110` | Unsigned remainder |

`3'b111` is **reserved**: the CPU Decoder must not issue it, even though the standalone MDU returns a deterministic zero if started with this code.

**Example:** `rd=r1, rj=r2, rk=r3` produces the register field `0x00000C41`. Thus `MUL.W r1,r2,r3` is `32'h001C0C41`, while `DIV.W r1,r2,r3` is `32'h00200C41`. These are examples, not new match values.

The MDU `op[2:0]` values above are **module-local control codes**, not the LoongArch instruction opcode field.

## 2. MDU RTL ports and protocol

```verilog
module mdu_iterative (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [2:0]  op,
    input  wire [31:0] operand_a,
    input  wire [31:0] operand_b,
    input  wire        result_ready,
    output reg         busy,
    output reg         done,
    output reg  [31:0] result,
    output reg         div_zero
);
```

`rst` is synchronous and active high. The MDU accepts a request on a rising edge only when `!rst && start && !busy && !done`. It latches `op` and both operands. Pulses of `start` during `busy` or `done` are ignored. No second request may be accepted while one operation or its unconsumed result is outstanding.

`busy=1` means the arithmetic algorithm is in progress. `done=1` means `result` and `div_zero` are valid; **`done` is held valid, not a one-cycle pulse**. A result is consumed only on a rising edge satisfying `!rst && done && result_ready`. While `done && !result_ready`, `done`, `result` and `div_zero` must remain stable. After consumption, `done` deasserts and the result can no longer be used for another EX/MEM transfer.

The current RTL takes 32 arithmetic iterations for multiplication and for nonzero-divisor division/remainder. For zero divisors (or the reserved op) it makes the result valid on the request-acceptance edge. One instruction still transfers its result to EX/MEM only once.

## 3. Decoder integration without modifying stable `decoder.v`

Add `rtl_test_only/mdu_decode_v08.v` as an auxiliary decoder. In ID, overlay these signals on top of the unchanged stable Decoder's outputs **only if `id_is_mdu`**:

| CPU decode/control signal | For a recognized MDU instruction |
|---|---|
| `id_is_mdu` | `1` |
| `id_mdu_op[2:0]` | Table in section 1 |
| `rs1_addr` | `inst[9:5]` (`rj`) |
| `rs2_addr` | `inst[14:10]` (`rk`) |
| `rd_addr` | `inst[4:0]` (`rd`) |
| `rs1_used`, `rs2_used` | `1`, `1` |
| `reg_write` | `1` (architectural r0 remains write-suppressed) |
| `mem_read`, `mem_write` | `0`, `0` |
| `branch_type` | `0` |
| `alu_src_imm` | `0` |
| `wb_sel` | ALU/result path, `2'b00` |
| `valid` / `supported_instruction` | recognized MDU is supported |

The existing `id_ex_reg.v` already carries the full `ex_inst`, destination register, operands and control bits. The V0.8 EX stage may decode `ex_inst` with a second instance of `mdu_decode_v08` instead of changing a stable pipeline-register interface. This is an **integration choice**, not a requirement to change the standalone MDU.

## 4. V0.8 EX integration and single-start/single-retirement contract

The V0.8 candidate datapath defines an `mdu_started` register for the MDU instruction currently held in ID/EX:

```verilog
wire ex_mdu_valid = ex_valid && ex_is_mdu;
assign mdu_start_fire = !rst && ex_mdu_valid && !mdu_started &&
                        !mdu_busy && !mdu_done &&
                        !ex_operand_wait && !mem_stall;
assign mdu_result_fire = !rst && ex_mdu_valid && mdu_started &&
                         mdu_done && !mem_stall && !ex_operand_wait;
assign mdu_hold = ex_mdu_valid && !(mdu_started && mdu_done);
```

- `mdu_start_fire` is both the physical `start` input and the once-per-instruction acceptance event. On its rising edge, `mdu_started` is set to 1. Neither repeated EX stall cycles nor an asserted `start` from other sources may create another acceptance.
- `operand_a = ex_forwarded_a`, `operand_b = ex_forwarded_b`; **both are the final EX-stage forwarded register operands**, not the pre-forwarding ID/EX saved operands or the ALU immediate selector.
- `mdu_started` remains 1 during computation and while `done` is pending. It clears after `mdu_result_fire` (or reset); the held ID/EX MDU instruction advances at the same clock edge as the result transfer.
- `result_ready` connects **directly** to `mdu_result_fire`, with no registered extra cycle or speculative readiness.
- On a rising edge where `mdu_result_fire=1`, EX/MEM has `stall=0` and `flush=0` for the MDU operation, so the exact same edge samples `ex_effective_result=mdu_result` into EX/MEM. On that edge the MDU consumes its `done` result and `mdu_started` clears. The MDU instruction must leave ID/EX then, preventing a second transfer.
- If `done=1` but `mem_stall=1`, `mdu_result_fire=result_ready=0`; EX/MEM holds the older memory operation and the MDU's `done/result/div_zero` remain stable until the actual acceptance edge.
- The arithmetic result uses the existing `ex_mem_reg.ex_alu_result` to `mem_alu_result` path, then `mem_wb_reg.mem_wb_data` to WB `wb_data`. `wb_sel=ALU` for MDU. No new HI/LO registers or side-effect path.

This section records the **proposed/current candidate implementation**, not a claim that V0.8 CPU integration has already passed Vivado simulation.

## 5. Pipeline priority, forwarding and MEM coexistence

- **Highest priority: synchronous reset.** It cancels MDU activity/pending results, clears pipeline validity and terminates outstanding memory work according to existing V0.7 reset semantics.
- **Older MEM access:** `mem_stall` prevents overwriting EX/MEM. Older MEM/WB data already present must be allowed to write once and subsequently be replaced by invalid bubbles rather than held as a repeated WB.
- **EX MDU waiting:** hold the current ID/EX instruction and its destination/control; hold IF/ID and stop accepting further IF responses. Insert/maintain an invalid EX/MEM bubble when EX is not ready to advance but MEM can advance. Do not block an older MEM instruction or its WB solely because `mdu_busy=1`.
- **Completed MDU + older MEM Stall:** do not bubble or overwrite EX/MEM; hold MDU result until both `done` and actual EX/MEM acceptance.
- **Forwarding:** MDU starts from post-forwarding EX A/B. When its result enters EX/MEM, it becomes eligible for normal EX/MEM forwarding in the next cycle; if it advances to MEM/WB, the ordinary WB forwarding path applies. `rd=0` never produces an architectural write. Never forward the MDU result before a valid EX/MEM/MEM-WB producer exists.
- **Load-use:** recognize MDU's `rj` and `rk` as used source registers; use existing hazard logic. A dependent load must become available before MDU `start`; pending EX/MEM load cannot incorrectly forward its address as data.
- **Branch:** redirect only when EX can genuinely advance (no `mem_stall`, no EX operand wait, no active MDU hold). Branch must not redirect repeatedly while frozen; wrong-path younger instructions are flushed, older MEM/WB actions preserved.
- **Cache IF backpressure:** an already-returned response must be held through stalls; no dropping/reissuing an outstanding request to simulate stall. Existing V0.7 adapter and PC/IF request handshake stay unchanged.

In the current V0.8 candidate datapath, `front_stall = mem_stall || ex_operand_wait || mdu_hold`. Branch resolve/redirect are gated by `!front_stall`; IF/ID and ID/EX are held on `front_stall`; EX/MEM is stalled on `mem_stall` and bubbled for an unready EX instruction only when MEM can advance. The stable `pipeline_control_unit.v` is not directly overwritten by this new control.

## 6. Divide-by-zero, signed overflow and Reset

The following are the **existing `mdu_iterative.v` module conventions**, not newly introduced CPU exception behavior:

| Case | Result | `div_zero` |
|---|---|---|
| `DIV.W` or `DIV.WU`, divisor `0` | `32'hFFFF_FFFF` | 1 |
| `MOD.W` or `MOD.WU`, divisor `0` | Original `operand_a` | 1 |
| `DIV.W`, `0x80000000 / 0xFFFFFFFF` | `32'h80000000` | 0 |
| `MOD.W`, `0x80000000 % 0xFFFFFFFF` | `32'h00000000` | 0 |
| `MOD.W`, negative non-multiple, e.g. `-13 % 5` | `-3` = `32'hFFFFFFFD` | 0 |

For divide by zero, `done` becomes valid on the request-acceptance edge and remains high until the `done && result_ready` edge; it does **not** trigger an architectural exception in V0.8. Signed quotient truncates toward zero; a nonzero signed remainder has the dividend's sign. Regular multiplication never raises an overflow exception.

Reset is synchronous and active high. On a clock edge with `rst=1`, the MDU cancels an in-progress multiplication/division **or an already-completed unconsumed result**, clearing `busy`, `done`, `result`, `div_zero` and its internal state. The CPU must also cancel the corresponding `mdu_started`/ID/EX transaction; no post-reset ghost WB or delayed result handshake is permitted.

## 7. Verification and approval checklist

### Module-level (reported completed by teammate B)

- Seven operations with signed/unsigned arithmetic and high/low products
- Positive, negative, zero, extreme operands and overflow
- Division-by-zero result and `done` timing
- 32-iteration latency for nonzero operations
- `start` ignored during `busy` and pending `done`
- Stable `done/result/div_zero` under `result_ready=0`
- Reset during `busy`, reset during pending `done`, and post-reset restart
- Reported Vivado 2019.1: **22 cases, 227 checks, 0 errors**

### CPU-level (must be demonstrated on the new V0.8 RTL; NOT YET VERIFIED here)

- Exactly one `mdu_start_fire` and one `mdu_result_fire` per retired MDU instruction
- Seven actual 32-bit LA32 machine codes decoded into the exact table in section 1
- ALU -> MDU, MDU -> ALU, MDU -> Branch and back-to-back MDU data dependencies
- MDU busy together with *older* DMEM Stall; no overwrite of EX/MEM
- MDU done together with DMEM Stall: stable result until actual EX/MEM acceptance
- Older WB may retire while younger MDU is busy; no duplicate WB or Store commits
- Load-use hazard before MDU start and I-Cache pending-response hold
- Reset in both active-operation and pending-result states; no ghost WB
- Wrong-path instructions cannot start, commit or write RAM after Branch redirect
- Exact WB PC / rd / data, Store PC / address / data Scoreboards, timeouts and zero errors
- Vivado 2019.1 compile order checked; `Missing instances` must be `< empty >`

**Merge gate:** first achieve basic V0.8 integration simulation and legacy V0.7 program regression in Vivado, then independent concurrent-stall/reset regressions by teammate B. A PASS screenshot for the MDU *module* cannot be used as proof of V0.8 *whole CPU* success.

## 8. Ownership and baseline discipline

- **Teammate B:** independent MDU RTL and module-level regression; later independent V0.8 CPU regressions/review.
- **Teammate A:** auxiliary MDU decoding, new V0.8 CPU top/datapath, memory and fetch integration, base CPU Scoreboards.
- Develop on `feature/pipeline-v08-cpu-integration`, starting from current `feature/pipeline-cpu-integration` with PR #34/#35 present.
- Add this interface document to `docs/pipeline_cpu/v08_mdu_interface.md` in the V0.8 branch; avoid changing historical V0.7 RTL and stable MDU RTL.
- PR back into `feature/pipeline-cpu-integration` only after actual compile/simulation evidence; teammate B reviews before merge.

## 9. Reference notes

Machine-code match values and `0xFFFF8000` mask cross-checked with GNU/LoongArch opcode tables (`opcodes/loongarch-opc.c`); arithmetic meanings conform to the LoongArch LA32 and LoongArch basic-architecture reference manuals. The module-level special-case outputs for division by zero are deterministic **implementation conventions**, not additional LoongArch instructions or architectural traps.
