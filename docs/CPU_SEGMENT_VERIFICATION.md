# CPU segment-register instruction verification

The optional `ENABLE_SEGMENT_REGISTERS` profile connects `mfsr`, `mfsrin`,
`mtsr`, and `mtsrin` to the committed segment-register bank. This verification
covers instruction decode, privilege, captured operands, retirement ownership,
request cancellation, and the router's prepared-write protocol. The feature
requires the existing supervisor and live-context profile and is independent
of `ENABLE_RUNTIME_BAT`.

The instruction and register contract comes from the local *MPC603e & EC603e
RISC Microprocessors User's Manual*, §2.3.6.3.2 and Table 2-41 (PDF page 123),
and the segment descriptor contract in [SEGMENT_REGISTERS.md](SEGMENT_REGISTERS.md).
For T=0, HDL descriptor bits 27:24 are cleared on write; T=1 is stored as an
opaque 32-bit word. The CPU does not yet use these SRs for page translation.

## Independent checks

| Bench | Coverage | Result |
|---|---|---:|
| `tb_segment_cpu_decode` | Four XO forms across all sixteen direct indices and register numbers, indexed RB dependencies, Rc and reserved-field rejection, feature-off/default profiles, and runtime-BAT coexistence | 22,913 checks |
| `tb_core_segment_csr` | Direct and indexed read/write, T=0 normalization, opaque T=1, RS/RB alias, r0 as a real RS/RB value, exact retirement commit, held acknowledgment, held-offer kill, same-edge prepare/kill, result kill, latest retained redirect target, and error diagnostics | 722 checks |
| `tb_core_segment_privilege` | All four forms in problem state; precise Program entry at `0x700`, saved PC/syndrome, handler execution, zero CSR requests, and no destination write | 652 checks |
| `tb_segment_runtime_service` | Prepared proposal, commit/abort/ack lifecycle and legacy/default kind behavior | 66 checks |
| `tb_segment_runtime_router` | Routed CPU CSR protocol, ordering, cancellation, and context exclusion | 54 checks |

The core bench uses its own external segment bank model. It checks that a
prepared write remains invisible during retirement stalls and changes the
selected entry only when `segment_csr_commit_o` coincides with accepted
retirement. A killed request or response cannot mutate the bank. Two retained
external redirects to the same unfinished instruction confirm that the latest
target is used after its committed CSR operation.

The privilege bench enters problem state through RFI before attempting each
form. The faulting instruction is converted to a privileged Program event
before the segment transport sees it. The default-disabled and enabled-without-
runtime-BAT decoder profiles are checked separately; existing legacy benches
keep all new CSR pins inactive.

Run from `sim/`:

```sh
make lint-segment-integration
make -j2 test-segment-cpu-decode test-core-segment-csr \
  test-core-segment-privilege test-segment-runtime-service \
  test-segment-runtime-router
```

The three strict integration lint profiles cover a segment-only core, a core
with both runtime BAT and segment CSR support, and a router with both services.
The existing `tb_segment_registers` default-profile bench remains in the full
regression after widening its request/response kind fields and tying off the
new optional transaction pins. The repository-wide prelint gate reported 152
passing profiles after the segment interface tieoffs. Broader firmware and
full-regression results are tracked in the project status documents.

These checks do not establish page-table translation, direct-store execution,
TLB refill, or complete 603e timing behavior.

## Parent integration gate

The full legacy regression finished with exit 0 against unchanged production
RTL, including all 243 Python checks.
The five new segment targets and three lint profiles were added after the full
invocation parsed its Makefile and passed separately through their canonical
targets. All nine firmware workloads passed; the segment negative control
failed the intended readback mailbox. See [SEGMENT_FIRMWARE.md](SEGMENT_FIRMWARE.md).
All 260 final source/manifest/configuration hashes
remained stable. No FPGA fit was run.
