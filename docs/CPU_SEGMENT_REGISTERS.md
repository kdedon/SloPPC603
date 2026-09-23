# CPU segment-register instructions

The opt-in `ENABLE_SEGMENT_REGISTERS=1` core profile implements the 603e's four 32-bit segment-register move instructions through the serialized supervisor lane. It requires `ENABLE_LIVE_CONTEXT=1` and `ENABLE_SUPERVISOR_EXCEPTIONS=1`. It is independent of `ENABLE_RUNTIME_BAT` and of the current MSR.IR/DR values. The canonical 16-word bank is the external `ppc_segment_registers` service behind `ppc_bat_memory_router`; the core contains no second segment-register bank.

The local 1997 *MPC603e & EC603e RISC Microprocessors User's Manual* Table A-28 (PDF page 386) and §2.3.6.3.2 (PDF page 123), and the local *Programming Environments* instruction pages 570, 572, 587, and 591, were checked for the exact fields and supervisor classification. The detailed source notes and T=0/T=1 descriptor policy are in [SEGMENT_REGISTER_CONTRACT.md](SEGMENT_REGISTER_CONTRACT.md).

| Instruction | XO | Operand capture | Result |
| --- | ---: | --- | --- |
| `mfsr rD,SR` | 595 | Direct `SR=insn[19:16]` | Selected descriptor to GPR D |
| `mfsrin rD,rB` | 659 | Indexed `SR=old rB[31:28]` | Selected descriptor to GPR D |
| `mtsr SR,rS` | 210 | Direct SR and old rS word | One selected SR write at retirement |
| `mtsrin rS,rB` | 242 | Old rS word and old rB high nibble independently | One selected SR write at retirement |

All forms require primary opcode 31 and `insn[0]=0`. Direct forms require bit 20 and bits 15:11 zero; indexed forms require bits 20:16 zero. Other encodings remain on the project's invalid/unsupported path. PR=1 on a valid form becomes a privileged-instruction program exception before the move acquires GPR or service write permission. GPR0 is an ordinary source or destination, and the source/index alias cases use values captured before the instruction writes a destination.

The core and router use a single request, response, commit/abort, acknowledgment, and idle protocol named `segment_csr_*`. A write request only prepares a private proposal. The committed bank changes once on the matching completion tag's accepted retirement edge. A canceled offered request completes its handshake, is aborted, and has its response drained before the lane releases ownership. Reads and accepted writes wait for frontend and memory quiescence, hold a fence, and refetch from the latest retained redirect target after successful retirement. A service error is a diagnostic fault and does not commit or redirect. The same internal lane retains runtime BAT behavior when both features are enabled.

The external bank normalizes T=0 writes by clearing bits 27:24 and retains T=1 descriptors as opaque words. The CPU lane does not interpret those fields. This increment adds no page-TLB use, page-table walk, translated instruction/data access, or new architectural context snapshot pins. Architectural software must honor the synchronization sequence and physical-mapping restriction in [SEGMENT_REGISTER_CONTRACT.md](SEGMENT_REGISTER_CONTRACT.md).

## Verification

Independent focused benches pass: exact decode and reserved-field rejection (22,913 checks), CPU CSR lifecycle and retained redirect behavior (722 checks), and supervisor privilege across all four forms (652 checks). The existing runtime BAT abstract core and privilege regressions still pass (885 and 488 checks). Default, segment-enabled and combined runtime-BAT/segment core lint pass. These results cover the CPU instruction and CSR boundary, not page translation.
