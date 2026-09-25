# Segment-register foundation contract

This source-reviewed contract covers the segment-register descriptor and instruction boundary. A sixteen-entry standalone bank and an opt-in CPU path for four serialized SR instruction forms now exist. The CPU path uses retirement-prepared writes and reads against that same bank. The opt-in router now also snapshots it after a clean BAT miss and submits a page-hit lookup to the existing TLB service. Page-table search, miss SPRs/TGPRs, architectural miss exceptions and a full software-managed MMU remain separate dependencies. The transaction details are in [SEGMENT_RUNTIME_PROTOCOL.md](SEGMENT_RUNTIME_PROTOCOL.md) and [PAGE_PATH_PROTOCOL.md](PAGE_PATH_PROTOCOL.md).

## Sources and exact encodings

The primary files are the workspace-root `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf` (MPC603EUM/AD, 11/97) and `MPCFPE.pdf` (Programming Environments, revision 1, 1/97). All PDF page numbers below are one-based. The 32-bit instruction descriptions apply; the adjacent temporary 64-bit-bridge/SLB descriptions do not apply to the 603e.

| Evidence | Exact source |
| --- | --- |
| Sixteen 32-bit SRs; data/main and instruction/shadow arrays both updated by a segment write | 603e UM §1.3.1.9, PDF 59 / printed 1-19 |
| All four forms operate independently of MSR.IR/DR | 603e UM §2.3.6.3.2/Table 2-41, PDF 123 / 2-45 |
| SRs are supervisor-only MMU registers | 603e UM Table 5-6, PDF 214 / 5-18; privilege exception rule §2.3.2.4.2, PDF 98 / 2-20 |
| Exact four instruction layouts | 603e UM Table A-28, PDF 386 / A-26 |
| `mfsr` operation and privilege | PEM PDF 570 / 8-158 |
| `mfsrin` operation and privilege | PEM PDF 572 / 8-160 |
| `mtsr` operation and privilege | PEM PDF 587 / 8-175 |
| `mtsrin` operation and privilege | PEM PDF 591 / 8-179 |
| T=0 and T=1 register layouts | PEM §2.3.6, Figures 2-23/24 and Tables 2-17/18, PDF 93–94 / 2-31–32 |
| Reserved-register-bit behavior | PEM Chapter 2 introduction, PDF 63 / 2-1 |
| Segment-write synchronization delegated to PEM | 603e UM §5.5.4, PDF 246 / 5-50 |
| Data/instruction synchronization and implicit-branch restriction | PEM §2.3.18/Tables 2-22/23, PDF 102–106 / 2-40–44 |
| Context versus execution synchronization | PEM §4.1.5, PDF 159–160 / 4-9–10; SYNC distinction PDF 229 / 5-3 |
| Hard-reset SR contents unknown; SPRGs zero | 603e UM §4.5.1.1/Table 4-8, PDF 177 / 4-19 |
| Soft reset does not initialize latches | 603e UM §4.5.1.2/Table 4-9, PDF 178 / 4-20 |
| SRs have no architectural valid bit and require initialization | 603e UM §5.4.3.1 continuation, PDF 223 / 5-27 |

The SR field diagram and hard-reset table were also visually inspected. No 601-specific register behavior or reset values were substituted.

All four instructions have primary opcode 31, an exact ten-bit XO in HDL `insn[10:1]`, and reserved `insn[0]=0`. There are no Rc/OE variants.

| Form | XO | Mask/value for exact decoding | Operands and result |
| --- | ---: | --- | --- |
| `mfsr rD,SR` | 595 | `fc10ffff / 7c0004a6` | D=`insn[25:21]`, SR=`insn[19:16]`; copy selected SR to GPR D |
| `mfsrin rD,rB` | 659 | `fc1f07ff / 7c000526` | D=`insn[25:21]`, B=`insn[15:11]`; copy SR selected by **old GPR B[31:28]** to D |
| `mtsr SR,rS` | 210 | `fc10ffff / 7c0001a4` | S=`insn[25:21]`, SR=`insn[19:16]`; copy GPR S to selected SR, subject to the defined reserved-bit policy |
| `mtsrin rS,rB` | 242 | `fc1f07ff / 7c0001e4` | S=`insn[25:21]`, B=`insn[15:11]`; write SR selected by old GPR B[31:28] from old GPR S |

The direct forms reserve HDL bit 20 and bits 15:11. The indexed forms reserve bits 20:16; they have no rA operand or zero-base convention. Manual rB[0–3] means the **most significant** four bits of the 32-bit GPR, not its low nibble. GPR0 is an ordinary source/destination. `mfsrin rB,rB` must capture the index before overwriting the same GPR; `mtsrin rS,rS` uses the old source word for both index and payload.

A valid encoding executed with PR=1 causes a privileged-instruction program exception, with no GPR/SR or other architectural write. Wrong reserved bits must not decode as these reviewed forms; use the project's existing invalid/unsupported classification rather than treating a reserved field as an additional register selector. Legal reads write only GPR D; writes affect only one SR. CR, XER, LR, CTR, MSR and memory remain untouched. IR/DR being zero does not disable the instructions or bypass their privilege check.

## Fields and reserved-bit policy

For T=0, the exact HDL layout is:

| Field | Manual bits | HDL bits | Meaning |
| --- | --- | --- | --- |
| T | 0 | 31 | Zero selects normal page translation |
| Ks | 1 | 30 | Supervisor protection key |
| Kp | 2 | 29 | Problem-state protection key |
| N | 3 | 28 | No instruction execution |
| Reserved | 4–7 | 27:24 | Not VSID bits |
| VSID | 8–31 | 23:0 | 24-bit virtual segment ID |

Recommend storing `write_data & 32'hf0ffffff` for T=0 and returning that normalized word on reads. This makes reserved bits read zero, including after software writes ones, which the PEM permits. Reserved **register data** is not a reserved **instruction encoding**: do not raise an illegal/privileged exception merely because a legal `mtsr` source contains ones in bits 27:24. The general PEM rule permits writes to reserved bits; their readback may be zero or, after a one was written, otherwise undefined. Zero normalization is an explicit selected implementation behavior rather than a claim that silicon preserves those bits.

For T=1, the format changes: HDL [28:20] is BUID and [19:0] is controller-specific information; N and VSID no longer have their T=0 meanings. The bank retains the complete 32-bit T=1 word as an opaque descriptor and return it unchanged, using mask `ffffffff`. **Do not apply the T=0 reserved mask to T=1 data.** This is a register-storage policy grounded in the PEM's T=1 format, not implementation of the direct-store facility. The 603e does not support direct-store accesses (UM chapter 5 introduction PDF 197 / 5-1; Table 5-3 PDF 211 / 5-15). A page-path lookup with T=1 must return the existing explicit unsupported condition and no usable PA; it must not reinterpret the low 24 bits as a VSID and succeed through a TLB hit. Full ISI/DSI generation remains unimplemented at this boundary.

A single shared sixteen-word architectural bank can supply both instruction and data contexts in the bounded serialized service. This preserves coherent write visibility without reproducing the silicon's duplicated arrays or their timing. No independent instruction-only or data-only SR update is exposed.

SRs have no architectural validity bit. On silicon hard reset their contents are unknown, and system software initializes them before enabling translation. The current bank uses deterministic zero on RTL reset as an explicit local initialization policy; it is not a guaranteed 603e reset state. It must not be credited as proving that software initialized translation context. If a later soft-reset input is added, preserve the bank: soft reset does not reinitialize those latches. Do not reuse the TLB service's local reset-invalid behavior as an invented architectural SR-valid flag.

## Required ordering and next interface

PEM Table 2-22 requires a context-synchronizing operation **before and after** `mtsr`/`mtsrin` for data accesses. Table 2-23 requires one **after** the write for instruction access; no additional preceding instruction-context synchronization is required by that table. Instructions between the two synchronization boundaries may use either context. A valid simple software sequence is `isync; mtsr ...; isync`, provided the instruction mapping remains valid throughout it. SYNC is execution synchronizing, not context synchronizing, and is not a general replacement for these ISYNC boundaries.

Table 2-23 note 5 additionally forbids an implicit physical branch: the physical instruction address of the segment-writing instruction and every following instruction through the next context synchronization must be independent of whether the alteration has taken effect. Do not advertise arbitrary self-remapping code as architecturally supported merely because a local flush happens to make it run. Changing PTE memory and ensuring R/C writes or other memory effects have completed may require additional SYNC/TLB invalidation work; that is distinct from the SR-only sequence.

The current bank has a committed valid/ready service with explicit read/write/index selection, PR and captured source data. A read/write response retains selected SR index, read data and privilege/unsupported status under backpressure. Legacy direct kind-1 writes change on accepted committed requests; the opt-in CPU uses kind-4 preparation and changes the committed SR exactly on retirement commit, never on decode, speculative issue or response consumption. An offered unaccepted write cannot alter either instruction or data context. The opt-in router now requests a kind-2 snapshot from this sole bank after a clean BAT miss. Router ownership blocks later SR mutation until the accepted memory transaction completes; the captured descriptor then drives the TLB lookup, independent of live SR changes.

The opt-in router latches EA and the selected `SR[EA[31:28]]` together before submitting the normalized request to `ppc_tlb_service`. It passes T, N, Ks, Kp, VSID, accepted PR, access bank and read/write intent from that captured context. The TLB service is never driven by a live SR and is not reset merely because an SR write occurs. Its registered EA/PA/WIMG/permission response remains owned until consumed.

Changing a segment's VSID naturally changes TLB matching; old translations for the previous VSID may remain and can be reused when that VSID is restored. Changing Ks/Kp/N affects permissions of a retained translation because these controls accompany each lookup. There is **no automatic whole-TLB flush** in the reviewed `mtsr` semantics. Reusing a VSID for different page mappings without required invalidation is a software/context-management error, not a reason to ignore VSID tags. Existing indexed invalidation clears the selected two ways in both banks, as described in [`TLB_SERVICE.md`](TLB_SERVICE.md).

The existing explicit-way normalized TLB refill is exposed as a test/control interface for this page-hit integration. Do not derive its VSID from whatever SR happens to be current unless the refill protocol proves that it belongs to the captured miss context. Architectural refill integration still needs IMISS/DMISS, ICMP/DCMP, RPA, SRR1.WAY and software handler semantics; SR storage alone does not supply them.

The opt-in actual-core SR instruction path connects the serialized supervisor lane's exact completion identity to prepared SR writes and GPR reads. Precise cancellation, stalled retirement, privilege faults and one-time commit require focused CPU tests; the service/router protocol tests alone are insufficient. The opt-in router now binds captured SR context to a page TLB lookup on clean BAT misses. Page-hit execution still requires tests that old accepted instruction obligations drain, stale prefetched work clears, and execution refetches in the post-sync context; CQ emptiness alone does not establish that property. The existing opt-in ISYNC commit/refetch mechanism is a dependency. Page misses and denials remain diagnostics without architectural page-fault delivery.

## Acceptance across runtime SR and page-hit stages

1. Exercise all sixteen direct selectors and every indexed high nibble, with low rB bits varied independently. Include r0, read-destination/source alias, and `mtsrin rS,rS` old-value cases. Literal words include `mfsr r3,15 = 7c6f04a6`, `mtsr 15,r3 = 7c6f01a4`, `mfsrin r3,r4 = 7c602526`, and `mtsrin r3,r4 = 7c6021e4`.
2. Verify PR=1 denies reads and writes without effects, independently of IR/DR. Mutate every reserved encoding field, including direct bit 20 and indexed bits 20:16, without accidentally accepting it as the same form. Check unchanged CR/XER/LR/CTR and unrelated GPRs/SRs.
3. Verify T=0 source `7fabcdef` reads `70abcdef`, retaining T/Ks/Kp/N and all 24 VSID bits. T=1 `8fabcdef` must retain the opaque descriptor under the storage policy and never become a successful ordinary-page translation. Test switching T formats in the same SR.
4. Feed both TLB banks from one SR update. Use two VSIDs mapping the same EA to different PAs; switch A→B→A without flush and verify correct retained entries. Alter only Ks/Kp/N and verify permissions change without altering cached RPN/WIMG. Then change a PTE/refill and explicitly invalidate to prove stale translation removal.
5. Stall a translation reply while offering a context write; prove the old snapshot remains fixed and the offered write has no early effect. Accept turnover and prove only later lookups see the new context. Cover simultaneous held reads, management privilege rejection, reset and selected-entry isolation.
6. For integrated page-hit execution, execute a legal synchronization sequence from code whose physical mapping does not change, with delayed old fetch/data responses. Verify old-context obligations drain and post-ISYNC execution uses the new translated context. This remains a separate acceptance gate from standalone bank and TLB correctness.

The first three cases cover SR instruction and descriptor behavior. Cases four through six cover the bounded opt-in page-hit integration and its synchronization boundary; any untested case remains an open gate. This contract document itself does not supply implementation or completeness credit.

## Independent SPRG0–3 check

SPRG0, SPRG1, SPRG2 and SPRG3 are architectural SPR numbers **272, 273, 274 and 275**, respectively. UM Figure 2-1 PDF 81 / 2-3 identifies the numbers; PEM `mfspr` Table 8-10 PDF 568 / 8-156 and `mtspr` Table 8-15 PDF 585 / 8-173 explicitly mark every one supervisor-only for both directions. The instruction's split SPR field must be decoded into the architectural number rather than treating contiguous encoded bits as that number. Neighboring unsupported SPRs must not alias the four-entry bank.

They are ordinary full-width 32-bit OS storage on the 603e, with no reserved subfields or architectural side effects from their contents (UM §1.3.1.10.2 continuation PDF 61 / 1-21 and §2.1 continuation PDF 84 / 2-6; PEM §2.3.8/Figure 2-26 PDF 95–96 / 2-33–34). Their conventional exception-handler uses are software conventions, not automatic exception-entry or exception-return updates.

**Hard reset explicitly sets SPRGs to `00000000`** in UM Table 4-8, PDF 177 / 4-19. This is different from the unknown SR/BAT/TLB contents in the same table. Soft reset §4.5.1.2/Table 4-9 PDF 178 / 4-20 does not initialize latches and changes SRR0/SRR1/MSR, so preserve SPRGs across a separately modeled soft reset. An ordinary program exception, SC or RFI must not clear the bank. These findings were sent directly to the SPRG implementation owner; no mismatch in number or privilege was found.
