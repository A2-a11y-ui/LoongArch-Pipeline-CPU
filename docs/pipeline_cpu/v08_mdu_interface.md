# V0.8 Iterative MDU Interface Specification

**Project:** LoongArch-Pipeline-CPU  
**Module:** `mdu_iterative`  
**Language/tool target:** Verilog-2001 / Vivado 2019.1  
**Status:** Draft implementation package; module-level Vivado simulation must be run before merge.

## 1. Supported operations

All results are 32 bits and are written to architectural `rd` by the CPU integration. No HI/LO architectural registers are added.

| `op[2:0]` | Instruction | Result |
|---|---|---|
| `000` | `MUL.W` | Low 32 bits of signed 32×32 product |
| `001` | `MULH.W` | High 32 bits of signed 32×32 product |
| `010` | `MULH.WU` | High 32 bits of unsigned 32×32 product |
| `011` | `DIV.W` | Signed quotient, truncation toward zero |
| `100` | `DIV.WU` | Unsigned quotient |
| `101` | `MOD.W` | Signed remainder; sign follows dividend |
| `110` | `MOD.WU` | Unsigned remainder |
| `111` | Reserved | Deterministic result zero; CPU decoder must not issue it |

## 2. Port contract

| Port | Direction | Width | Meaning |
|---|---|---:|---|
| `clk` | input | 1 | Rising-edge clock |
| `rst` | input | 1 | Synchronous, active-high reset |
| `start` | input | 1 | One-cycle request pulse |
| `op` | input | 3 | Operation code |
| `operand_a` | input | 32 | First operand |
| `operand_b` | input | 32 | Second operand |
| `result_ready` | input | 1 | Consumer can accept completed result |
| `busy` | output | 1 | Iterative calculation in progress |
| `done` | output | 1 | Result is valid and awaiting acceptance |
| `result` | output | 32 | Result data |
| `div_zero` | output | 1 | Result belongs to a divide-by-zero operation |

## 3. Request acceptance

A request is accepted on a rising edge only when:

```verilog
start && !busy && !done && !rst
```

There is no separate `start_ready` port in this interface. The producer must issue `start` as a one-cycle pulse and must not retry while `busy` or `done` is high. `op`, `operand_a`, and `operand_b` are latched at acceptance; their external values may change afterward.

A start pulse presented while `busy=1` or `done=1` is ignored.

## 4. Result handshake

A completed result is accepted on a rising edge when:

```verilog
done && result_ready && !rst
```

While `done=1` and `result_ready=0`, `done`, `result`, and `div_zero` remain stable. A new request cannot be accepted until the pending result has been consumed. After the handshake, `done` clears and the unit returns to idle.

The CPU must connect `result_ready` to the actual EX/MEM acceptance condition. In particular, it must remain low if a completed MDU result cannot yet advance because an older MEM transaction is blocking the pipeline.

## 5. Latency and internal architecture

- `MUL.W`, `MULH.W`, `MULH.WU`: 32 shift-add iterations.
- Non-zero `DIV.W`, `DIV.WU`, `MOD.W`, `MOD.WU`: 32 restoring-division iterations.
- Divide-by-zero: deterministic result and `done` asserted on the request-acceptance edge.
- Reserved operation: result zero and `done` asserted on the request-acceptance edge.
- `busy` is high during the 32 iterative steps. It is low when `done` is asserted.

The multiplier uses a 64-bit accumulator, a 64-bit shifted multiplicand and a 32-bit shifting multiplier. Signed multiply operations use operand magnitudes and apply two's-complement sign correction to the final 64-bit product.

The divider uses a 33-bit partial remainder and a 32-bit quotient shift register. Signed operations divide magnitudes, then apply quotient and remainder signs.

## 6. Divide-by-zero and overflow behavior

V0.8 does not introduce an architectural exception/trap path for divide-by-zero. To guarantee deterministic simulation and CPU behavior, this module fixes the following implementation results:

- `DIV.W` / `DIV.WU`, `operand_b == 0`: `result = 32'hFFFF_FFFF`, `div_zero = 1`.
- `MOD.W` / `MOD.WU`, `operand_b == 0`: `result = operand_a`, `div_zero = 1`.
- All other completed operations: `div_zero = 0`.
- `0x8000_0000 / 0xFFFF_FFFF` (`DIV.W`): `0x8000_0000`.
- `0x8000_0000 % 0xFFFF_FFFF` (`MOD.W`): `0x0000_0000`.

`div_zero` is a diagnostic status associated with the held result. It clears only when the result is accepted or reset is asserted.

## 7. Reset

Reset is synchronous and active high. On a rising edge with `rst=1`:

- Any in-progress multiply/divide operation is canceled.
- Any completed but unconsumed result is discarded.
- `busy=0`, `done=0`, `result=0`, `div_zero=0`.
- No stale result is emitted after reset release.

The MDU has no memory side effects, so reset cancellation only clears its internal transaction state.

## 8. Integration requirements for CPU V0.8

The CPU integration must ensure:

1. `start` is generated exactly once for each valid MDU instruction.
2. EX holds the MDU instruction and its destination/control metadata while `busy=1`.
3. Younger ID/IF instructions do not overwrite the held EX instruction.
4. Older MEM/WB instructions may retire while MDU is running, subject to existing pipeline rules.
5. A completed result remains held while EX/MEM cannot accept it (`result_ready=0`).
6. The MDU result is not forwarded before `done=1`.
7. The result enters EX/MEM exactly once after `done && result_ready`.
8. WB commits the MDU instruction exactly once to `rd`.
9. Reset cancels an in-flight MDU operation and prevents stale WB after restart.
10. Branch redirect and older multi-cycle MEM backpressure retain their existing priority and validity rules.

## 9. Verification plan

`tb_mdu_iterative.v` covers:

- All seven supported arithmetic operations.
- Positive and negative multiplication.
- Low-product truncation and high-product extraction.
- Signed and unsigned division and remainder.
- Negative dividend and negative divisor sign rules.
- Divide-by-zero deterministic outputs and `div_zero`.
- Signed overflow corner case.
- Zero dividend and divisor larger than dividend.
- Exact 32-cycle iterative latency for non-zero operations.
- `done/result/div_zero` stability under `result_ready=0`.
- Ignoring `start` while busy or while a result is pending.
- Reset abort and clean post-reset restart.

The testbench is supplied as source only. The Vivado 2019.1 result must be recorded after the user runs it; no PASS result is pre-filled.
