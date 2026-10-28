## Summary

Add V0.6 IFetch subsystem **simulation-only** integration and self-checking testbench. This combines the official team-A `if_id_reg.v` with team-B's existing I-Cache Adapter V0.5.1 and two-way LRU Cache.

## Files

- `rtl_test_only/if_pc_driver_v06.v` — **test-only** PC driver, not official pipeline IF control.
- `rtl_test_only/ifetch_subsystem_v06.v` — integration harness, not hardware/CPU top.
- `tb/tb_ifetch_subsystem_v06.v` — 9-case joint verification.
- `docs/` — acceptance record and next integration handoff.

## Verified in Vivado 2019.1

- Official team-A IF/ID Register used (confirmed by teammate B).
- Total errors: **0**; **ALL TESTS PASSED**.
- Total requests: **24**, responses: **12**; valid deliveries: **11**, error responses: **1**.
- Cache count displayed at end is not the whole-run hit rate (test uses resets).

## Covered

Sequential fetch, cache miss and backpressure, redirect during miss/held response/completion edge, flush vs stall, synchronous reset priority, invalid fetch, redirect+flush+stall.

## Safety / Scope

- No change to official CPU27 top, Decoder, I-Cache or Adapter.
- **Not** yet verification of team-A official PC/IF controller, five-stage CPU execution, or final FPGA implementation.
- Please review test-only file placement, handshake, IF/ID capture/flush semantics, and compatibility with the upcoming official PC/IF controller.

## Next

Integrate team-A official PC/IF controller and rerun joint fetch suite before freezing V1.0 interface.
