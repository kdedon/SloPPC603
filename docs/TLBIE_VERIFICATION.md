# CPU `tlbie` verification

`make -C sim test-tlbie-decode` passes **6,370 checks**. The fixed-literal oracle uses `0x7c000264 | (RB << 11)` for primary opcode 31/XO 306, exercises every RB register including r0, and rejects every nonzero reserved RT and RA value, Rc=1, and adjacent XO values. It also checks the default-disabled decode and absence of GPR, flag, memory, and branch writes.

`make -C sim test-core-tlbie` passes **905 checks** against an independent prepared-invalidate model. The model starts with both ITLB and DTLB valid in all 32 sets and changes only the indexed set on the exact `tlbie` retirement commit edge. It checks RB r3 and the old full r0 value, a held retirement, delayed acknowledgement, cancellation before request acceptance, same-edge request/kill, cancellation while response is withheld, result-publication kill, latest retained redirect target, service error, and reset during a delayed acknowledgement. Cancelled operations leave every modeled set valid; committed operations clear the same set in both banks while neighboring sets remain valid.

`make -C sim test-core-tlbie-privilege` builds two feature profiles. The enabled problem-state profile passes **322 checks** across RB r0 and r31: each operation enters Program Priv with SRR0/SRR1 and handler-visible state checked, without a TLB transport offer or architectural register write. The default-disabled supervisor profile passes **37 checks** across the same RB values: it preserves the existing illegal diagnostic halt, with no TLB transport, exception-state write, or handler execution.

The runtime service and router protocol benches are separate focused tests (`test-tlb-runtime-invalidate-service` and `test-tlb-runtime-invalidate-router`). The older standalone TLB oracle retains its external 93-bit request and 90-bit response vectors: it zero-extends the incoming two-bit kind and asserts the high response-kind bit remains clear with runtime invalidation disabled. Every old direct core/router fixture drives the new opt-in transport inactive for strict `-Wall` lint.

The CPU test model verifies its own index update at commit and lifecycle isolation. End-to-end prefilled I/D mapping behavior is covered by the compiled firmware and router protocol tests; the CPU bench does not claim to observe internal TLB arrays.

## Integrated acceptance, 2026-09-22

The parent accepted `make -C sim -j6 regression` with exit 0, 36 RTL lint
configurations, 165 strict testbench lint profiles, and all 243 Python checks.
The default-disabled TLBIE configuration also passed its separate strict build
and 37-check simulation (its command was added after the broad make parsed its
recipes). The runtime service and router suites passed 96 and 134 checks.
All eleven compiled profiles passed; the new TLBIE ELF ran three modes, and
the wrong-set negative was rejected as documented in [TLBIE_FIRMWARE.md](TLBIE_FIRMWARE.md).
The 43 recorded production inputs and 275 final source/configuration inputs
were unchanged at acceptance. No FPGA fit was run. Local broad-gate log:
`/tmp/ppc-tlbie-regression.log`; these temporary logs are not durable CI storage.
