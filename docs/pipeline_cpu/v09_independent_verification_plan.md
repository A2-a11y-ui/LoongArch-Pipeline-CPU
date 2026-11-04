# V0.9 Independent Verification Plan

**Project:** LoongArch Pipeline CPU  
**Verification Branch:** `test/pipeline-v09-verification`  
**Integration Branch:** `feature/pipeline-cpu-integration`  
**Version:** V0.9 Draft 0.1  
**Role:** Team A — Independent Verification

## 1. Verification Objectives

The objective is to independently verify the V0.9 FPGA CPU implementation, including:

- Five-stage pipeline functionality.
- Instruction decoding and execution.
- Data forwarding and hazard handling.
- Iterative MDU integration.
- Multi-cycle DMEM and I-Cache interaction.
- Pipeline backpressure and recovery.
- Reset and transaction cancellation.
- Exactly-once register writeback and Store commitment.
- FPGA implementation and EGO1 hardware behavior.

The verification environment must not depend solely on internal RTL signals or waveform inspection.

## 2. Verification Methodology

Use an independent Testbench with:

1. Instruction memory or I-Cache response model.
2. Data memory model with configurable latency.
3. Independent reference register model.
4. In-order WB scoreboard.
5. Store commitment scoreboard.
6. Request/response transaction counters.
7. Timeout and deadlock detection.

All tests must have defined input programs, expected results, observed results and pass/fail conditions.

## 3. Test Categories

### 3.1 Basic Pipeline Tests

- Arithmetic instructions.
- Immediate instructions.
- Register writeback.
- Load and Store.
- Sequential instruction execution.

### 3.2 Data Hazard Tests

- EX/MEM forwarding.
- MEM/WB forwarding.
- Consecutive RAW dependencies.
- Load-use dependencies.
- ALU-to-MDU dependencies.
- MDU-to-ALU dependencies.
- MDU-to-Store dependencies.

### 3.3 Control Hazard Tests

- Taken branches.
- Not-taken branches.
- Consecutive branches.
- MDU-dependent branches.
- Wrong-path WB suppression.
- Wrong-path Store suppression.

### 3.4 MDU Tests

- MUL.W
- MULH.W
- MULH.WU
- DIV.W
- DIV.WU
- MOD.W
- MOD.WU

Boundary cases:

- Zero operands.
- Positive and negative operands.
- Signed and unsigned boundaries.
- Division by zero.
- INT_MIN / -1.
- Negative signed remainder.
- Consecutive MDU instructions.
- MDU result backpressure.

### 3.5 Memory and Cache Tests

- Multi-cycle Load.
- Multi-cycle Store.
- Delayed responses.
- Response holding.
- I-Cache miss and recovery.
- IF response during MEM Stall.
- MDU and MEM concurrent stalls.

### 3.6 Reset Tests

- Reset while idle.
- Reset during MDU Busy.
- Reset after MDU Done but before acceptance.
- Reset during outstanding memory transaction.
- Correct restart after reset.

## 4. Scoreboard Requirements

Every valid WB event must be checked against:

- Commit PC.
- Destination register.
- Expected writeback data.
- Expected instruction order.

Every Store event must be checked against:

- Store PC.
- Memory address.
- Store data.
- Exactly-once commitment.

The test must fail on:

- Duplicate WB.
- Missing WB.
- Duplicate Store.
- Missing Store.
- Wrong-path side effects.
- Unexpected memory transactions.
- Timeout or deadlock.

## 5. Initial Verification Status

| Category | Status |
|---|---|
| Instruction inventory | Pending Decoder audit |
| Basic pipeline | Pending V0.9 top-level |
| Data hazards | Pending |
| Control hazards | Pending |
| MDU integration | Pending |
| DMEM interaction | Pending |
| I-Cache interaction | Pending |
| Reset | Pending |
| FPGA synthesis verification | Pending |
| EGO1 hardware test | Pending |

## 6. Evidence Requirements

For each test, retain:

- Testbench source.
- Machine-code program.
- Expected result table.
- Actual simulation log.
- Error count.
- Relevant waveform screenshot.

For FPGA testing, additionally retain:

- Synthesis report.
- Implementation report.
- Timing report.
- Resource utilization report.
- Bitstream generation result.
- EGO1 board testing evidence.

## 7. Acceptance Criteria

1. All supported instructions in the verified instruction inventory pass their functional tests.
2. At least 25 supported instructions are verified, subject to the course requirement.
3. No unexpected WB or Store commitment.
4. No lost or duplicated transactions.
5. All hazard and backpressure tests pass.
6. No unexplained timeout or deadlock.
7. Synthesis and implementation complete successfully.
8. EGO1 hardware results match the expected program outputs.

No test may be declared passed merely because its waveform appears normal.