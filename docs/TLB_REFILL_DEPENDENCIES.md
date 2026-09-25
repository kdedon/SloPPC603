# CPU software TLB refill: architectural dependencies

Status update, 2026-09-23: the three CPU-seeded load rounds below are accepted.
See [CPU_TLB_LOAD.md](CPU_TLB_LOAD.md) and [TLB_LOAD_VERIFICATION.md](TLB_LOAD_VERIFICATION.md).
The opt-in response-bound miss diagnostic is accepted separately under
[PAGE_MISS_RESULTS.md](PAGE_MISS_RESULTS.md). Clean page PP/N/G exceptions
have separate opt-in contracts in [PAGE_DATA_EXCEPTIONS.md](PAGE_DATA_EXCEPTIONS.md)
and [PAGE_INSTRUCTION_EXCEPTIONS.md](PAGE_INSTRUCTION_EXCEPTIONS.md).
The pure hash/compare derivation and full-width CPU SDR1 state are accepted
([MISS_DERIVATION.md](MISS_DERIVATION.md)); the four-register TGPR overlay is
also accepted ([TGPR_REGISTER_FILE.md](TGPR_REGISTER_FILE.md)). Bounded opt-in
miss exception entry, automatic miss SPR capture, and a compiled four-event
handler are accepted with focused and full regression evidence ([EXCEPTION_TLB_MISS.md](EXCEPTION_TLB_MISS.md)). PTE
table search, PTE R/C writeback, replacement-state updates, and the manual
conflicts below remain open. This document preserves the source audit and
original CPU-load plan.

This source audit originally planned CPU `tlbld`/`tlbli` and a software
miss-handler slice. The service has two 32-set, two-way banks and an external
normalized refill port; the router translates page hits and can return opt-in
precise miss diagnostics. CPU `tlbie` and `tlbld`/`tlbli` now have separate
retirement-owned service paths. A newer opt-in path enters bounded 603e miss
exceptions and runs a compiled handler; full regression acceptance is recorded
in [SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md). It
does not yet search PTEGs or update PTE R/C bits. The source below is the local
*MPC603e & EC603e RISC Microprocessors User's Manual* (`../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, 11/97). Page numbers are one-based PDF pages, followed by printed pages.

| Required state or behavior | Confirmed 603e source | Minimum CPU/router implication |
| --- | --- | --- |
| Precise I miss, D load miss, D store miss | §4.5.12–14 and Table 4-16, PDF 191–193 / 4-33–35; §5.5.2, PDF 231–235 / 5-35–39 | A page miss (and the documented store/C=0 case) needs a typed, nonsticky result for the exact accepted fetch/load/store, with its EA, access kind, old PC/context and cancellation identity. Older instructions and memory effects must finish; a killed younger access must not install miss state. An I miss saves the next instruction to execute in SRR0; a data miss saves the faulting instruction so `rfi` can retry it. |
| Miss vectors and exception context | §4.2.2, PDF 173 / 4-15; §4.5.12–14/Table 4-16, PDF 191–193 / 4-33–35 | The vector offsets are I miss `0x01000`, D load miss `0x01100`, D store miss `0x01200`. Exception entry clears IR/DR, enters supervisor state and sets MSR[TGPR]. MSR[IP] selects a physical `0x000n_nnnn` or `0xFFFn_nnnn` vector. SRR1 must carry the saved MSR and miss-specific fields atomically with the vector redirect. |
| IMISS/DMISS | §2.1.2.2, PDF 87 / 2-9; §5.5.2.1.1, PDF 232 / 5-36; SPR selector Table 2-39, PDF 121–122 / 2-43–44 | SPR 980/976 captures the instruction/data effective **page** address at miss entry, before later SR or MSR changes. DMISS is big-endian even with MSR[LE]=1. Provide supervisor MFSpr access and preserve distinct I/D capture. The manual conflicts on software writes (see below). |
| ICMP/DCMP | §2.1.2.3, PDF 87–88 / 2-9–10; §5.5.2.1.2, PDF 233 / 5-37; Table 2-39, PDF 121–122 / 2-43–44 | SPR 981/977 captures the matching PTE high word from the selected miss-time SR and EA: V, 24-bit VSID, H and six-bit API. These registers are supervisor read/write. The overview says TLB load uses their upper 25 bits plus 11 address bits from rB; the detailed chapter more generally says the compare word is loaded. For software-seeded loads, require compare API to equal rB API so both descriptions yield the same TLB tag. Do not recompute a captured miss value from a later SR snapshot. |
| HASH1/HASH2 and SDR1 | §2.1.2.4/Figure 2-6/Table 2-5, PDF 88 / 2-10; §5.5.2.1.3, PDF 233 / 5-37; Table 2-39, PDF 121–122 / 2-43–44 | SPR 978/979 exposes physical primary/secondary PTEG addresses for the **last acknowledged** I or D miss. Upper bits 0–6 come from SDR1. The handler searches eight PTEs per PTEG (§5.5.2.2, PDF 234–235 / 5-38–39). This needs an SDR1 state/read-write path and miss-time hash calculation; the normalized TLB management port has neither. HASH1/2 are read-only. |
| RPA | §2.1.2.5/Figure 2-7/Table 2-6, PDF 89 / 2-11; §5.5.2.1.4, PDF 234 / 5-38; Table 2-39, PDF 122 / 2-44 | SPR 982 is software read/write. Handler writes the matching PTE second word: RPN bits 0–19, R bit 23, C bit 24, WIMG bits 25–28, PP bits 30–31; bits 20–22 and 29 are reserved. The load ignores R. PTE memory R/C updates and ordering remain software work. |
| SRR1.WAY, KEY, CR0, type | §4.1.1/Table 4-4, PDF 169 / 4-11; §5.5.2.1/Table 5-10, PDF 231–232 / 5-35–36; Table 4-16, PDF 192 / 4-34 | Manual bit 14 (`SRR1[17]` in HDL) selects refill way, initially chosen by replacement state and writable by software. Bit 12 KEY comes from miss-time `PR ? Kp : Ks`; bit 13 identifies I/D miss; bit 15 identifies load/store; bits 0–3 save CR0 and must be restored by the handler. Implementing WAY requires per-bank/set victim-selection state or a documented deterministic local policy, then an architectural SRR1 write path that changes the selected way for the later load. |
| TGPR0–3 and `rfi` | §2/Table 2-1, PDF 83 / 2-5; §5.1, PDF 215 / 5-19; §5.5.2.1, PDF 231 / 5-35 | MSR[TGPR] is manual bit 14 (`MSR[17]` HDL), set on each miss; it overlays four temporary registers on GPR0–3 while preserving the normal GPR values. GPR4–31 use in this mode is undefined. `rfi` clears MSR[TGPR] (Table 2-1 and Table 4-5 explicitly say so); the handler restores CR0 from SRR1. A failed table search must explicitly clear TGPR and restore CR0 before branching to an ordinary ISI/DSI handler. The opt-in live-context mode now permits TGPR only with PR, EE, IR and DR clear; the normal GPR bank remains intact. |
| `tlbld rB` / `tlbli rB` | §2.3.8, PDF 125–126 / 2-47–48; §5.5.2.1/Table 5-9, PDF 231 / 5-35 | Both are supervisor-only 603e instructions, primary opcode 31, XO 978/1010; manual operand fields 6–10 and 11–15 and Rc are zero (HDL instruction bits 25:16 and 0); rB is manual bits 16–20 (HDL instruction bits 15:11) and is the only GPR field. Full **old rB**, including r0 as a register, supplies EA; manual EA bits 15–19 (`EA[16:12]` HDL) choose the set, while SRR1.WAY chooses the way. `tlbld` consumes DCMP+RPA; `tlbli` consumes ICMP+RPA. They alter no GPR/flags. Run with IR=DR=0 as recommended by the manual; translated execution has additional synchronization and prefetch constraints. |

**Resolved miss-field conflicts from the manual's own handler.** Use SRR1 manual bit 15 = 0 for load, 1 for store (HDL mask `0x00010000`). Table 4-4 (PDF 169 / 4-11) and Table 5-4 (PDF 211 / 5-15) agree; the data-miss handler comments (PDF 242–243 / 5-46–47) say store=1, and its synthesized DSI path copies SRR1 bit 15 to DSISR store bit 6 with `rlwinm r1,r3,9,6,6` (PDF 245 / 5-49). The opposite wording in Tables 4-16 and 5-10 is inconsistent with this executable example. Preserve miss-time KEY in SRR1 manual bit 12 (HDL mask `0x00080000`) from `PR ? Kp : Ks`: Table 4-4, Table 5-10/Figure 5-11 (PDF 232 / 5-36), and the handler's `andis. r3,r3,0x0008` key test (PDF 245 / 5-49) agree. Table 4-16's “bits 4–12 cleared” cannot apply to KEY. These resolutions use the local primary manual's worked assembly; no hardware erratum was located in this workspace.

**Still unresolved.** The programming overview says DMISS/IMISS are software read/write (§2.1.2.2, PDF 87 / 2-9); the detailed memory chapter calls them read-only (§5.5.2.1.1, PDF 232 / 5-36). Overview Figure 2-5/Table 2-4 labels compare bit 25 reserved (PDF 88 / 2-10), while detailed Figure 5-13/Table 5-11 identifies it as H, cleared on miss (PDF 233 / 5-37). The manual's `tlbli` page appears to say `tlbld` once in a caution paragraph; its opcode and main operation remain unambiguous. Software writes to miss SPRs, LRU victim updates, I/D collision priority, and R/C writeback need explicit contracts and tests. For a failed table search, §§4.5.12–14 (PDF 192–193 / 4-34–35) require the miss handler to restore machine state and clear MSR[TGPR] before synthesizing an ISI or DSI; leaving temporary GPRs active when branching to the ordinary handler would corrupt its register view.

The historical compiled timer firmware layout put main at `0xfff01000`
([`toolchain/README.md`](../toolchain/README.md)). Since §4.2.2 (PDF 173 / 4-15) maps IP=1 vectors
into `0xFFFn_nnnn`, the I-TLB miss vector is **`0xfff01000`** and collided
with that main address. The dedicated miss-entry image now reserves the three
0x100-byte vector slots and moves main to `0xfff02000`; the older prefilled-hit
firmware did not exercise a miss handler.

**Bounded miss-entry implementation.** CPU-seeded TLB loads and the
response-bound diagnostic packet are accepted. The packet carries accepted
EA, captured SR/PR/IR/DR/write and follows the existing response/cancellation
identity; the core completion packet supplies the faulting PC. The newer
opt-in implementation installs SRR0/SRR1 and the appropriate IMISS/DMISS,
ICMP/DCMP and HASH1/2 state at the accepted oldest miss boundary, sets TGPR,
and redirects to the physical vector. It supports CPU `mfspr` reads of the
captured registers and uses a documented deterministic WAY choice, without
claiming LRU replacement. Standalone exception tests and a compiled
four-event handler passed focused checks; broad regression acceptance is
pending. The original test requirements remain useful for ongoing validation:
all three vectors with both IP values, delayed older operations, canceled
younger misses, miss-time SR changes, exact SRR1 fields/WAY, TGPR overlay and
`rfi` restoration, and high-vector placement. PTE search and R/C memory
effects remain separate work.

## Historical three CPU-seeded load rounds

These accepted rounds provided a usable **CPU-seeded TLB load** before the
later opt-in miss-entry implementation. The separate diagnostic packet is
accepted. DMISS/IMISS/HASH state, TGPR, and vector entry are now implemented
with focused evidence, while broad acceptance remains pending; PTE search and
R/C writeback remain future work. The steps below are historical implementation
scope. Existing normalized management refill stays available for tests and is
not used to execute a CPU load.

1. **Prepared refill in the sole TLB service.** Add an opt-in kind-5 `PREPARE_REFILL` to `rtl/ppc_tlb_service.sv`. It captures bank, rB EA, VSID, selected way, RPN/C/WIMG/PP and a held status response but changes no valid/tag/data bit. Reuse the serialized prepare-commit/abort/held-ack pins already used by kind-4 `tlbie`; retain the accepted kind in the reservation so commit performs exactly the intended mutation. The normalized tag remains `{VSID, EA[27:17]}`; set is EA[16:12]. Duplicate rejection must compare the proposed tag with the opposite way without evicting either entry. Abort and rejected prepare preserve all committed entries. Reset discards a pending proposal without applying it, while following the service's existing local reset policy of invalidating all entries. Keep existing already-authorized kind-1 management refill behavior. Add direct service tests for held response, no early mutation, single commit/ack, abort/kill, duplicate rejection, and coexistence with kind 4; update [`docs/TLB_SERVICE.md`](TLB_SERVICE.md) and its service-only lint/test target. No router or CPU semantics are implied by this round.
2. **CPU-visible software seed state.** Add `ENABLE_TLB_LOAD=0` to `rtl/ppc_core.sv`/`rtl/ppc_special.sv` (requires live context and supervisor exceptions, independent of `ENABLE_TLB_INVALIDATE`). Extend the existing supervisor `mfspr`/`mtspr` selector whitelist in `rtl/ppc_decode.sv` for **DCMP 977, ICMP 981 and RPA 982 only** (UM Table 2-39, PDF 121–122 / 2-43–44); add full 32-bit committed storage/readback in `ppc_special.sv`. A write takes effect once at matching retirement, never when dispatched or merely offered; canceled and privilege-faulted writes do not change state. A read samples committed state and is killed with its instruction. Preserve all 32 bits, including fields whose load semantics are not yet enabled; interpret/check them only in round 3. Existing SPR 27 (`SRR1`) already has an architectural full-width `mtspr`/`mfspr` path, so software can seed manual bit 14/WAY (HDL bit 17) without a new register bank. Do not add DMISS/IMISS, HASH1/2, SDR1, automatic miss writes, or a private TLB. Test selector bit reversal, all three read/write roundtrips, r0 source/destination, retirement backpressure, redirect cancellation, privilege exceptions with zero mutation, and unchanged BAT/SR/TLBIE behavior. Test files belong under `tb/` with new `sim/Makefile` targets and a short CPU seed-state note.
3. **Retirement-owned CPU `tlbld`/`tlbli`.** Decode primary opcode 31, XO 978/1010 with manual bits 6–15 and Rc zero (HDL bits 25:16 and 0; rB is HDL bits 15:11) (§2.3.8, PDF 125–126 / 2-47–48). Capture the full old rB value, including r0; `tlbld` selects DCMP and data bank, `tlbli` ICMP and instruction bank. Before offering a prepared request, require a well-formed seeded value: compare V=1 (HDL bit 31), H=0 (HDL bit 6), compare API (HDL bits 5:0) equal rB manual EA4–9 (HDL bits 27:22), and RPA reserved bits 20–22/29 zero (HDL bits 11:9/2). This is a **bounded accepted-input contract**, not a claim about silicon behavior for malformed software seeds. The accepted VSID is compare HDL bits 30:7, set is rB[16:12], low five tag bits rB[21:17], way is committed SRR1[17], RPN is RPA[31:12], C is RPA[7], WIMG is RPA[6:3], PP is RPA[1:0]; RPA.R is ignored. Because API agreement is required, the service's existing full tag from rB[27:17] matches either manual phrasing. Route a separate CPU `tlb_fill_req_valid/ready`, `bank`, `ea[31:0]`, `vsid[23:0]`, `way`, `rpn[19:0]`, `c`, `wimg[3:0]`, `pp[1:0]`, held `rsp_valid/ready/error`, `commit`, `abort`, held `ack_valid/ready`, and `idle` through `rtl/ppc_core_bat.sv`/`rtl/ppc_bat_memory_router.sv` to service kind 5. The core holds the existing MMU fence, drains older obligations, prepares without mutation, commits at matching retirement, drains canceled offers/responses, waits for ack and refetches at the latest retained target. Require MSR.IR=DR=0 at `tlbld`/`tlbli` execution and return a bounded diagnostic for other modes; translated execution and prefetch hazards need separate ordering work. Verify all 32 sets, both banks/ways, VSID and API matches, r0, precise commit/abort, held ack, privilege, malformed-seed diagnostic, and preserved earlier entries. A compiled program should seed the three SPRs and SRR1.WAY with CPU instructions, execute both TLB loads in real mode, then enable IR/DR and prove physical I/D page hits **without external normalized TLB preloading**. This does not constitute software miss-handler refill.
