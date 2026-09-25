# CR0 and XER ownership for the width-one integer core

Status: accepted bounded implementation contract. The [CX-I02 state foundation](FLAGS_STATE.md) now implements packet deltas, committed registers and owner control; [CX-I03 record-logical execution](RECORD_LOGICAL.md) connects the first CR0 writers. It extends the ownership and recovery rules in [EXECUTION_CONTRACT.md](EXECUTION_CONTRACT.md), [RECOVERY_BACKEND.md](RECOVERY_BACKEND.md) and [CORE_RECOVERY.md](CORE_RECOVERY.md). The original 15 forms remain flag-free; record-logical forms add CR0 writes, and [ADD/ADDC](ADD_FLAGS.md) implements CA/OV/SO and record effects. [ADDE](ADDE.md) now also captures committed CA for carry-input addition; [ADDME/ADDZE](ADD_UNARY.md) extend it to decrement/increment. [RLWINM/RLWNM](ROTATE_EXECUTION.md) now use captured SO with final masked-result CR0 updates and preserve XER. [SLW/SRW](LOGICAL_SHIFTS.md) likewise preserve XER and record their final shifted result. The reviewed metadata in [isa.json](../sim/spec/isa.json) prepares ADD, register-logical, word-rotate and word-shift variants; metadata coverage does not enable their decode.

This contract admits one speculative instruction with flag dependencies or destinations. That resource restriction is a deliberate first implementation choice. It is not architectural instruction serialization, an assertion about the 603e's XER implementation, or acceptance of full chapter-6 timing. Independent instructions without flag effects can continue through the existing resources until ordinary in-order dispatch encounters a blocked instruction.

## Source decisions and limits

`UM` below means the local primary `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`. `601UM` means the explicitly secondary `MPC601UM.pdf`. PDF pages are one-based physical pages; printed pages are given separately.

| ID | Evidence and decision |
| --- | --- |
| CX-S01 | UM §2.1, printed 2-2 / PDF 80, identifies XER and distinguishes explicit from implicit register access, but refers register-set detail to the Programming Environments Manual. That manual is absent locally. Use the already reviewed shared ISA semantics from 601UM below, with this provenance visible. Do not import 601 implementation timing or its nonarchitectural XER compare-byte field. |
| CX-S02 | UM Table 4-8, printed 4-19 / PDF 177, specifies zero CR and zero XER after hard reset. Use zero initialization for the scaffold's global reset; this does not implement the full hard-reset exception sequence. |
| CX-S03 | UM §6.3.3–6.3.3.1, printed 6-12 / PDF 258, requires program-order architectural commitment, five completion buffers, one CR writeback per cycle and one CR rename register. A single outstanding record-form destination fits that resource bound. The combined CR/XER admission token below is a conservative design choice; the passage does not establish this XER scheme. |
| CX-S04 | UM §6.3.3.1–6.3.3.2, printed 6-13 / PDF 259, transfers renamed results on retirement and flushes younger results after a bad prediction. It separately lists `mtspr(XER)` and `mcrxr` as dispatch-serialized instructions. Those operations remain unsupported; they cannot later bypass the ownership rules here. |
| CX-S05 | 601UM §2.2.4.1, Table 2-3, printed 2-12 / PDF 58: Rc integer forms compare the 32-bit destination result algebraically against zero; CR0.SO copies the **final** XER.SO for that instruction. Therefore OE+Rc uses its own newly computed sticky SO, not its incoming SO and not OV alone. |
| CX-S06 | 601UM §2.2.5.2, Table 2-8, printed 2-16 / PDF 62: CA is carry/discard information; OE arithmetic replaces OV and accumulates SO; XER byte count occupies PowerPC bits 25–31. The table explicitly calls the bits 16–23 compare-byte field nonarchitectural. This design assigns no meaning to that field. The SO description's parenthetical `(OV)` is an editorial inconsistency, not a second SO location. |
| CX-S07 | 601UM `add`, `addc`, `adde`, `addme`, `addze`, printed 10-8/9/10/15/16 / PDF 562/563/564/569/570, supplies the ADD equations and conditional CA, OE and Rc effects used below. |
| CX-S08 | 601UM logical instruction pages: `and` 10-17 / PDF 571; `andc` 10-18 / 572; `or` 10-149 / 703; `orc` 10-150 / 704; `xor` 10-216 / 770; `nand` 10-146 / 700; `nor` 10-148 / 702; `eqv` 10-55 / 609. These change CR0 only when Rc is set and do not change XER. Primary encoding anchors remain in `isa.json`, `logical_family_semantics.encoding_source`. |
| CX-S09 | 601UM `rlwimi`, `rlwinm`, `rlwnm`, printed 10-155/156/157 / PDF 709/710/711: Rc observes the final merged/masked destination; XER is unchanged. Retain the already documented primary Table A-6 versus A-43 opcode conflict in the ISA source audit; this contract does not resolve it differently. |
| CX-S10 | 601UM Table 3-9, printed 3-24–25 / PDF 146–147, and `slw`, `srw`, `sraw`, `srawi`, printed 10-167/179/170/171 / PDF 721/733/724/725, establish the shift effects. Register shifts use the numeric low six count bits; `srawi` uses five. Preserve the reviewed editorial resolutions: the `slw` prose's bit 16 is bit 26; `sraw`/`srawi` rotate-like pseudocode must not override the arithmetic-shift prose and CA rules. |

The existing [TIMING_DECISIONS.md](TIMING_DECISIONS.md) distinction between dispatch, issue, accepted finish and commitment remains unchanged. Computing flag data early is permitted here; updating architectural flags early is not. Nothing in this contract reinterprets ambiguous figure cells as architectural commitment.

## State, numbering and masked writes

Use normal RTL vectors `[31:0]`; PowerPC bit 0 is the numeric MSB.

| Field | PowerPC numbering | RTL location |
| --- | --- | --- |
| CR0 LT, GT, EQ, SO | CR bits 0, 1, 2, 3 | `cr[31]`, `[30]`, `[29]`, `[28]` |
| Other CR fields | CR bits 4–31 | `cr[27:0]` |
| XER SO, OV, CA | XER bits 0, 1, 2 | `xer[31]`, `[30]`, `[29]` |
| XER byte count | XER bits 25–31 | `xer[6:0]` |
| Instruction OE / Rc | instruction bits 21 / 31 | `insn[10]` / `insn[0]` |

Keep full committed `cr[31:0]` and `xer[31:0]`, both reset to zero (CX-S02). The CR write mask is zero or `0xf0000000`; the only permitted XER write bits in this scope are `0xe0000000`. A retirement applies `(old & ~mask) | (new_bits & mask)` independently to both registers. Consequently CR1–CR7, XER byte count and every other XER bit retain their prior values. Reserved-bit preservation is the implementation's partial-write policy, not a claim that software can write or read arbitrary reserved bits architecturally. No current instruction can seed those bits; preservation tests may seed a standalone model or register-unit test fixture without claiming a supported instruction.

An instruction's allocation metadata fixes three independent write enables: `write_ca`, `write_ov_so`, `write_cr0`. OE arithmetic writes OV and SO together; CA may be written independently. Payload values never grant their own write permission. Unsupported encodings allocate the existing diagnostic packet with **no** GPR or flag writes and acquire no flag token.

Derive `xer_mask = (write_ca ? 0x20000000 : 0) | (write_ov_so ? 0xc0000000 : 0)` from those allocated enables. Pack CR candidate bits as `{CR0out, 28'b0}` and XER candidate bits as `{SOout, OVout, CAout, 29'b0}`, then store the masked delta at accepted finish (or store the equivalent separate masked fields). Bits outside the allocated mask are zero in the delta. A producer cannot choose another CR field, enable CA on a logical instruction or overwrite byte count. A future BF-selected compare destination requires a separately reviewed allocation-metadata extension.

## Per-family dependencies and effects

`Rc` and `OE` below are decoded legal modifiers, not indiscriminately interpreted bits of every instruction format. All legal forms in this scope also produce one GPR destination.

| Family | Reads CA | Reads SO | Writes CA | Writes OV/SO | Writes CR0 |
| --- | --- | --- | --- | --- | --- |
| `add` | no | OE or Rc | no | OE | Rc |
| `addc` | no | OE or Rc | yes | OE | Rc |
| `adde`, `addme`, `addze` | yes | OE or Rc | yes | OE | Rc |
| `and/andc/or/orc/xor/nand/nor/eqv` | no | Rc | no | no | Rc |
| `rlwimi/rlwinm/rlwnm` | no | Rc | no | no | Rc |
| `slw/srw` | no | Rc | no | no | Rc |
| `sraw/srawi` | no | Rc | yes | no | Rc |
| Existing `addi/addis/ori/oris/xori/xoris` | no | no | no | no | no |

“Reads SO” includes preserving sticky history while producing a new SO. The original flag slice had no architectural CR reader. The [serialized control lane](CONTROL_MEMORY.md) now reads committed CR after draining older work, and comparisons write any BF-selected field. OV and byte-count readers remain absent. Preservation uses the commit mask, not a speculative whole-register snapshot. `add` with OE=Rc=0 and all nonrecord logical/rotate/logical-shift forms need no flag token. `sraw` and `srawi` require it even with Rc=0 because they replace CA.

The 20 reviewed ADD encodings, 16 logical encodings, six rotate encodings and eight shift encodings retain their existing `isa.json` identities and legality checks. In particular `addme/addze` require reserved rB=0, X-form logical opcodes use the full ten-bit extended opcode (no OE interpretation), and r0 remains a real register except where a separately reviewed immediate instruction defines literal-zero rA.

## Result equations and intra-instruction ordering

Let `U(x)` be an unsigned 32-bit value, `S(x)` its signed two's-complement interpretation, `CAin` and `SOin` the captured committed bits, and `R` the final 32-bit GPR result. ADD uses a sufficiently wide unsigned sum for CA and a signed mathematical sum for OV:

| Family | Unsigned sum for result and CA | Signed mathematical sum for OV |
| --- | --- | --- |
| `add`, `addc` | `U(A) + U(B)` | `S(A) + S(B)` |
| `adde` | `U(A) + U(B) + CAin` | `S(A) + S(B) + CAin` |
| `addme` | `U(A) + 0xffffffff + CAin` | `S(A) - 1 + CAin` |
| `addze` | `U(A) + CAin` | `S(A) + CAin` |

`R` is the unsigned sum modulo 2^32. For a CA writer, `CAout` is unsigned sum bit 32. Widen the operands **before** addition. For OE=1, `OVout` is whether the mathematical signed sum lies outside [-2^31, 2^31-1], and `SOout = SOin OR OVout`. A nonoverflowing OE instruction clears OV but cannot clear an already set SO. For OE=0, OV/SO are not written, even when the mathematical operation overflows. Do not infer signed overflow from unsigned carry, and do not treat `addme`'s `0xffffffff` as positive in the signed overflow calculation (CX-S06–07).

For `sraw`, let `n = U(B) & 63`; for `srawi`, `n = SH` in [0,31]. Compute the sign-filled result according to the accepted shift metadata. Replace CA as follows:

| Count | CAout |
| --- | --- |
| 0 | 0 |
| 1–31 | source sign bit AND (any of the source's numeric low `n` bits is 1) |
| 32–63 (`sraw` only) | source sign bit |

The last case discards the entire source; a negative 32-bit source necessarily contains a one. This is an inference from the shared shift/discard rule and count behavior in CX-S10, not an additional printed equation. Positive sources clear CA even when one bits are discarded. Neither arithmetic-right shift writes OV or SO. Explicitly branch for count zero and counts at least 32 so host/RTL width-dependent shifts cannot accidentally define the mask. Logical shifts leave all XER bits untouched.

For every Rc=1 form, first compute the **final** GPR result, including any rotate mask and `rlwimi` merge with old rA. Then form:

```
LT = R[31]
EQ = (R == 0)
GT = !LT && !EQ
SO_for_CR0 = write_ov_so ? SOout : SOin
CR0out = {LT, GT, EQ, SO_for_CR0}
```

Thus `addo.` can produce a negative wrapped result, set OV/SO, and write CR0.LT=1/CR0.SO=1 in one instruction. CR0.SO is not cleared simply because the current instruction does not overflow. A nonrecord instruction never writes CR0, even when it updates XER. Exactly one of LT/GT/EQ is set for the fully defined results in this scope (CX-S05).

## One-owner admission and packet contract

Maintain `flags_busy` and `flags_owner: completion_tag_t`; identity is the existing CQ slot plus generation. Define `needs_flags` as any CA/SO read or any of the three flag write enables above. At an ordinary dispatch edge:

1. A `needs_flags` instruction requires `!flags_busy` in addition to the existing CQ, GPR-rename and RS resources. The pre-edge state decides availability. A retiring owner does **not** permit a new flag owner on that same edge.
2. Allocate CQ, GPR rename, RS and flag ownership atomically. Capture committed CA/SO at that edge into the operation's held inputs; unused input bits may be zero. A previous flag owner has already retired before this capture, so its architectural updates are visible. Older flag-free instructions do not threaten that snapshot.
3. The RS preserves those inputs while waiting for its independently tagged GPR operands. Keep existing same-edge GPR wake/capture/issue bypass and read-before-destination-map ordering. `rlwimi` must capture old rA as an actual source, including when it aliases rS; its partial GPR merge cannot use the newly allocated destination value.
4. Carry the required arithmetic controls and captured flag inputs through IU backpressure. Produce one indivisible tagged result containing GPR value and candidate CA/OV/SO/CR0 values. There is no second flag response and no early GPR-only finish for these instructions.
5. An accepted ownership-valid CQ finish stores that complete result and marks the instruction done once. Allocation metadata, rather than the result, selects destination and write enables. The GPR wake uses the allocated rename tag and result value as today. An invalid, stale, duplicate or recovery-killed result is consumed without changing CQ values, GPR rename, flag state or any wake.

Proposed minimal structural extensions are named here for review, not prescribed as already existing package fields: decoded `read_ca/read_so/write_ca/write_ov_so/write_cr0`; held `ca_in/so_in`; result `ca/ov/so/cr0`; and CQ/retirement's allocated write enables plus those result values. `needs_flags` is derived, not a separately trusted producer input. The flag-owner register does not create another CQ entry or a GPR rename slot. It needs no separate result buffer because the CQ holds the speculative delta.

Flag candidates never broadcast on the current GPR wake lane. There is no CA/SO forwarding in this first implementation: the next flag-dependent instruction waits through the owner's commitment. A younger **flag-free** GPR consumer may wake and execute from an owner's accepted GPR finish before that owner retires. This is safe because GPR forwarding is speculative, commitment is ordered and recovery cancels younger work. It must not cause the younger instruction to inherit or update flags.

## Commitment, recovery and edge priority

An owner's earliest issue/finish/commit edges retain the current D/E/F/C contract: issue at least D+1, unstalled accepted finish E+1, and commitment no earlier than the edge after finish. Flag computation does not add an unreviewed stage or enable finish-to-retire bypass.

At the finished CQ head's accepted retirement edge, update its GPR and both masked architectural flag registers **atomically** using one retirement handshake. If the head is stalled, all offered GPR and flag metadata/results remain stable, all architectural state remains unchanged, and ownership remains busy. Release the flag token only when that exact owner commits or is killed. A flag-free retirement cannot release it. The retirement interface and scoreboards must expose/check the same combined effects; an independently backpressured flag channel is outside this design.

Apply the existing pre-edge recovery classification:

- Reset clears committed CR/XER, token and all local producers/consumers together.
- An accepted prefix cut blocks dispatch, including flag acquisition. Determine owner survival by exact identity in the valid CQ prefix, using CQ traversal age; numeric slot order is irrelevant.
- If the owner is killed, clear its token and discard its speculative delta. A coincident response from that owner cannot finish or wake. Previously committed CR/XER remain unchanged.
- If the owner survives, retain its captured inputs, CQ delta/readiness and identity. A surviving unfinished owner may accept its complete result on the redirect edge, but cannot commit that newly finished result on that edge.
- A surviving pre-edge finished owner may commit on the redirect edge if ready; apply its masked flags and GPR once, then release the token. Classifying ownership from the **post-commit** survivor list naturally removes this owner. Keeping a stalled owner preserves it unchanged.
- A cut killing any pre-edge finished head remains rejected, ready or not, under the accepted irreversible-retirement policy. Rejected/misaligned/halted redirects have no cancellation effect and cannot suppress ordinary flag progress.

There is no flag map to rebuild: at most one flag owner can survive. Recovery must assert that the surviving CQ contains exactly the busy owner when one exists, and no second `needs_flags` allocation. Old-generation responses cannot reacquire ownership. Keep the current local cancellation and finite-generation lifetime assumptions: eight generation bits are not an unbounded replay defense. An external flag producer would require the explicit producer-lifetime extension before connection.

A diagnostic fault has no flag delta. If it follows an older flag owner, the older instruction may complete normally before the diagnostic halt. Killing an uncommitted diagnostic follows the existing exact fault-producer cleanup. A committed halt remains irreversible. This contract does not introduce architectural overflow exceptions: OE updates status; trap and program-exception semantics remain separate work.

## Implementation slices and acceptance gates

The following are implementation work, not validation already performed by this document. Each slice must keep unsupported variants illegal until all of its destination effects are connected.

| Slice | Required change | Acceptance evidence |
| --- | --- | --- |
| CX-I01 | Independent pure reference functions for ADD/shift flags, CR0 packing and masked commit, linked to the existing ISA profile IDs. | Directed arithmetic boundaries plus deterministic random checks; expected results use wide mathematical arithmetic and explicit bit selection, not a copy of the RTL expression. Check all legal OE/Rc combinations and reserved-field rejection. |
| CX-I02 | Package/result/CQ/retirement extensions and standalone committed-state/owner control. Initialize every added field, including diagnostic/tieoff paths. Keep current transport ownership validation. | Fill/wrap CQ; wrong index/generation, duplicate and killed results have no GPR or flag effects. Check complete packet stability under backpressure and atomic GPR+flags commit. |
| CX-I03 | Decode and IU support in bounded families, beginning with record logical forms or one ADD family. Acquire the token with dispatch; capture CA/SO; preserve operands through RS/IU stalls. | A second flag instruction waits until the edge after owner retirement. An independent flag-free instruction still dispatches when ordinary resources permit. Same-edge GPR wake/capture and owner commit plus nonflag dispatch remain correct. |
| CX-I04 | Extend backend/core recovery scoreboards to CR/XER and flag ownership. | Killed pending and finished-younger owners; kept stalled owner; surviving owner finish on redirect; surviving owner commit on redirect; rejected cut killing finished head; stale response after reuse; reset while owner is in RS, IU and CQ. |
| CX-I05 | Update architectural retirement trace and integrated program tests before declaring any flag form supported. | Compare committed GPR, full CR and full XER in program order under fetch, dependency and retirement stalls and redirects. Preserve existing no-flag regressions and strict RTL lint. Record the conservative admission timing in the stage contract when implemented. |

Minimum arithmetic adversaries include `0xffffffff + 1` (CA without signed overflow), `0x7fffffff + 1` (signed overflow without CA), and `0x80000000 + 0x80000000` (both). Exercise CAin=0/1 for every extended family. In particular `addme(0,0)` gives `0xffffffff`, CA=0, OV=0, while `addme(0x80000000,0)` gives `0x7fffffff`, CA=1, OV=1; `addze(0x7fffffff,1)` gives `0x80000000`, CA=0, OV=1. Test these as OE/Rc variants rather than treating OV as an unconditional write.

Ordering adversaries must include an overflowing OE instruction followed by a nonoverflowing OE instruction (OV clears, SO stays set), a record logical instruction after that pair (CR0.SO remains set), and a nonrecord CA writer between record forms (CR0 preserved). Seed CR1–CR7 and XER byte count/other bits in a unit fixture and prove every partial update preserves them. For shifts use zero, positive, `0x80000000`, `0xffffffff`, and negative even/odd values at counts 0, 1, 31, 32 and 63; check high count bits are ignored. For `rlwimi.` compare the merged result, not only the rotated/masked fragment.

Negative checker tests must deliberately mutate final-SO selection to incoming SO or OV, clear sticky SO on a nonoverflowing OE operation, change an untouched CA/CR field, accept a second owner at a release edge, let a killed owner wake, or commit only the GPR portion. Each mutation must be rejected by the corresponding independent expected relation; syntax-only checks are insufficient.

## Remaining decisions

This bounded contract is ready for implementation review without waiting for full CPU timing, bus, FP or exception completion. Its concrete prerequisite is coordinated extension of the existing single-result ownership and retirement path; simply adding ALU flags or widening decode is insufficient.

Before improving flag throughput, separately review per-field CA/SO dependencies, forwarding, partial-write WAW handling and available rename resources against primary 603e evidence. Before adding `mfcr`, `mtcrf`, compare/branch CR consumers, `mfxer/mtspr(XER)`, `mcrxr`, subtraction or multiply/divide, define their new reads/writes and any serialization explicitly. `addic.`, `andi.` and `andis.` have implicit CR0 effects but are outside this reviewed family set. The missing Programming Environments Manual remains a source-provenance gap; obtaining it should reconcile the adopted secondary shared semantics. None of those follow-ups changes the precise current token, mask or atomic-commit rules silently.

## Selected-field comparison extension

The control/memory milestone retains the exact CQ-tag flag owner and adds an allocation-controlled `cr_field` selector. Existing record forms use field zero. The historical `write_cr0` permission now enables one selected four-bit field: the completion result is shifted into that field, and committed flags apply the corresponding mask. Comparisons capture SO after older work drains and update no XER bits. The independent program checks all BF values, signed/unsigned immediate/register comparisons and preserved nonselected fields. This supersedes the CR0-only mask restriction for comparison packets; it does not add speculative flag forwarding.

## Round 26 selected CR-field transfer extension

[MFCR/MTCRF](CR_TRANSFERS.md) add full committed-CR reads and eight-bit FXM writes. The allocation-owned `write_cr_fields` permission and `cr_mask` select any combination of CR fields; the result's `value` carries the candidate and completion stores only selected bits in `cr_delta`. The flags unit independently masks retirement. Existing `write_cr0`/`cr_field` stays the one-field path; XER permissions are unchanged. MFCR drains older work before capturing CR and blocks younger dispatch until retirement. MTCRF owns the exact flag token even when FXM is zero. This supersedes the earlier statement that CR transfers remain unsupported, without adding flag forwarding or claiming 603e timing.

## Round 27 single CR-bit extension

[CR logical operations](CR_LOGICAL.md) add allocation-owned `write_cr_bit` and `cr_bit` for one architectural destination bit. Completion consumes only the Boolean candidate in `result.value[0]`, and both completion and retirement mask it independently. Both CR sources come from the pre-operation snapshot, including aliases. Multi-field MTCRF and single-field compare/record paths remain unchanged. No GPR or XER permission is granted, and the same exact-owner recovery contract applies.

## Round 28 CR-state extension

[MCRF/MCRXR](CR_STATE.md) reuse the selected-field `write_cr0` permission. MCRXR also allocates CA and OV/SO clearing; all effects retire atomically from one captured result. XER[28:0] remains preserved, with the reserved-bit source boundary recorded in that contract.
