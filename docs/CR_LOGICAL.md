# CR logical operations

Round 27 adds CRAND, CRANDC, CREQV, CRNAND, CRNOR, CROR, CRORC and CRXOR, bringing the reviewed executable subset to 135 forms.

## Source contract

All eight are opcode-19 XL forms. Word bits 25:21 select crbD, 20:16 select crbA and 15:11 select crbB. The full ten-bit XOs are respectively 257, 129, 289, 225, 33, 449, 417 and 193. Word bit 0 must be zero. Every index is an architectural CR bit number: zero means the numerical most significant CR bit.

The operations are AND, AND with complemented B, complemented XOR, complemented AND, complemented OR, OR, OR with complemented B, and XOR. Both sources are read before the destination is replaced, including all aliases. Only crbD changes; every other CR bit, all GPRs and XER are preserved. These are user instructions, with no Rc/OE variants.

Primary encoding anchors are 603e Appendix A.1 PDF362 and XL table A-37 PDF394. Secondary operation descriptions are 601UM PDF585–592, printed 10-31 through 10-38. Each concrete form retains its individual source and timing row in the ISA metadata. MCRF and MCRXR remain outside this slice.

## Implementation

The existing serialized special lane snapshots full committed CR after older work drains. A three-bit `cr_logic` operation and five-bit source indices select the Boolean result. Allocation grants `write_cr_bit` with five-bit `cr_bit`; `result.value[0]` supplies only the candidate Boolean value. Completion and architectural flags independently apply the allocated one-bit mask, and only retirement changes CR. Result data cannot enlarge the write permission. Existing multi-field MTCRF and one-field compare/record paths remain supported.

Killed unfinished work cannot update CR. A stalled finished head retains stable metadata and state; recovery may keep it, including a coincident commit, but cannot revoke an already offered head. These scheduling choices are functional scaffolding and do not establish 603e timing or dual-issue behavior.

## Validation

- Full-core symbolic program: 296,832 checks over 3,851 retirements, 140 executions per operation. It covers all four truth inputs, every destination bit, aliases and dependency chains, MFCR readback, nonzero XER, and memory/retirement stalls.
- Recovery: 44,991 checks across all eight operations and five cut scenarios, with destinations chosen so every operation changes a bit when retained.
- Coupled completion/flags: 4,016 checks, including every single-bit destination with both candidate values, poisoned unallocated fields/result bits, held-state preservation, diagnostic sanitization and prior mask/identity/recovery/wrap tests.
- Decoder: 524,288 checks cover every crbD/crbA/crbB combination and both values of reserved bit 0.

The expanded metadata comparison checks both opcode-19 and opcode-31 spaces: 26,048 compiled probes, 807 accepted, with zero overlaps across 135 reviewed forms. The broader register-transfer, arithmetic and recovery regressions remain required. Full CPU timing, exceptions, bus RTL, caches, MMU, floating point and FPGA closure remain separate tasks.
