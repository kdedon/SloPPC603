# Software-loaded 4-KiB TLB service

`rtl/ppc_tlb_service.sv` implements instruction and data TLB storage with a serialized, registered request/response interface. Each bank has 32 sets and two explicitly selected refill ways, for 64 translations per bank. The service retains its standalone interface and is now reused by the opt-in BAT-router page-hit path described in [PAGE_PATH_PROTOCOL.md](PAGE_PATH_PROTOCOL.md). The service itself does not perform real-mode or BAT translation, hold segment registers, search page tables, generate architectural exceptions, implement miss SPRs/TGPRs, or select replacement victims. The integrated page-hit path is not a full software-managed MMU.

The caller supplies the VSID and segment control bits belonging to the effective address. In the opt-in router, these come from an accepted snapshot of the sole committed SR bank after a clean BAT miss. The router invokes lookup only after deciding that enabled translation uses the page path. A miss produces no physical address; it never silently becomes identity translation. The two banks are real separate storage, but this interface arbitrates all requests through one response slot. Its throughput and response latency do not reproduce simultaneous 603e MMU operation or processor instruction timing.

## Primary source and bit mapping

Page numbers below are **one-based PDF pages**, followed by the printed page. The 603e source is `../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf` (MPC603EUM/AD, 11/97); the architectural source is `../MPCFPE.pdf` (MPCFPE/AD, revision 1, 1/97). Both are in the workspace root, one directory above `ppc603e`. The PEM is the [official NXP Programming Environments manual](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf), SHA-256 `0600de0a3cb81636b9d511aa6b185e2fccc02f895ce4630411725634ef8e7eee`. No 601 implementation-specific organization was imported.

| Reviewed relation | Exact local source |
| --- | --- |
| Separate instruction/data MMUs and independent TLBs | 603e UM §5 introduction, PDF 197 / 5-1; §5.1/Table 5-1, PDF 199 / 5-3 |
| 64 entries, two ways per bank; segment selection and TLB organization | 603e UM §5.1/Table 5-1, PDF 199 / 5-3; §5.4.3.1 and Figure 5-7, PDF 221–223 / 5-25–27 |
| Set index = manual EA15–19; tag = VSID24 + EA4–14; page offset = EA20–31 | 603e UM Figure 5-7, PDF 222 / 5-26 and comparison prose PDF 223 / 5-27 |
| Low entry word carries RPN, C, WIMG, PP; valid/tag belongs to high word | 603e UM §5.4.3.1, PDF 222–223 / 5-26–27; RPA Table 5-13/Figure 5-15, PDF 234 / 5-38 |
| Selected-way software refill; software can override LRU-selected SRR1[WAY] | 603e UM §5.5.2.1, PDF 231–234 / 5-35–38; Table 5-10, PDF 232 / 5-36; `tlbli`/`tlbld` descriptions on PDF 231 |
| One `tlbie` clears both indexed ways of both banks, without tag comparison; no `tlbia` | 603e UM §5.4.3.2, PDF 223 / 5-27 |
| Reset does not clear silicon TLB valid bits | 603e UM §5.4.3.1 continuation, PDF 223 / 5-27 |
| R is effectively one for all valid TLB entries; software clearing PTE R/C must invalidate cached translations | 603e UM §5.4.1.1, PDF 218 / 5-22; §5.4.1.2, PDF 219 / 5-23 |
| Store with C=0 requires software table-search/update work; denied store cannot set C | 603e UM Table 5-4, PDF 212 / 5-16; Table 5-7, PDF 218 / 5-22; §5.4.1.2, PDF 219 / 5-23; Figure 5-17, PDF 237 / 5-41 |
| Segment T/N and guarded instruction access conditions | 603e UM Table 5-3, PDF 211 / 5-15; Figure 5-16, PDF 236 / 5-40; Figure 5-19, PDF 239 / 5-43 |
| Key = PR ? Kp : Ks; exact page PP permission table | PEM Table 7-21 and surrounding prose, PDF 346 / 7-58 |

Figure 5-7, Figure 5-17 and PEM Table 7-21 were visually inspected as well as text-extracted. In HDL numbering, set index is `EA[16:12]`, page tag is `EA[27:17]`, and offset is `EA[11:0]`. EA[31:28] selects the caller's segment register and is **not** compared separately. Two segment numbers resolving to the same VSID therefore alias when their remaining page address agrees. Different VSIDs retain separate translations, including when only a high VSID bit differs. RPN is 20 bits and the allowed PA is `{RPN, EA[11:0]}`.

## Transactions and held responses

A request is accepted on a rising edge with `req_valid_i && req_ready_o`. With no runtime proposal or held commit acknowledgment, `req_ready_o = rst_ni && (!response_valid || rsp_ready_i)`. An accepted request captures its entire response and, for a successful kind-1 refill or kind-2 invalidate, changes storage at that edge. A held response blocks every following request; a runtime proposal or acknowledgment also reserves the slot. When an ordinary old response is consumed, one new request may be accepted on that same edge. Kinds 1 and 2 remain already-authorized committed management operations, exposed through the router's normalized test/control port. CPU `tlbie` instead uses opt-in kind 4: preparation is private, the indexed valid bits clear on retirement commit, and a registered acknowledgment is held until consumed. See [TLB_INVALIDATE_PROTOCOL.md](TLB_INVALIDATE_PROTOCOL.md).

Bank 0 is ITLB and bank 1 is DTLB. The service request and response kind fields are now three bits wide. All responses echo accepted kind, bank and EA. Payload outputs are meaningful only while `rsp_valid_o` is asserted.

| Kind | Inputs used | Behavior |
| --- | --- | --- |
| 0: lookup | bank, EA, VSID, PR, Ks, Kp, N, T, write | Registered hit/miss/access-condition result; never changes entries |
| 1: refill | bank, EA, VSID, PR, way, RPN, C, WIMG, PP | Supervisor-only explicit selected-way replacement, making that entry valid |
| 2: invalidate set | EA, PR | Supervisor-only invalidation of both ways in both banks at EA[16:12]; bank, VSID and remaining EA bits are ignored |
| 3: unsupported | kind, bank, EA | Explicit unsupported response, no state change |
| 4: prepare invalidate, opt-in | EA, PR | Supervisor-only private set proposal; both ways in both banks clear only on later retirement commit; disabled profile returns unsupported |

Refill and invalidate with PR=1 return `privileged` without modifying storage. The router now decodes CPU `tlbie` and presents its retirement-owned request as kind 4 to this service. Neither the normalized external management port nor this service decodes CPU TLB load instructions or exposes IMISS/DMISS, ICMP/DCMP, RPA, SRR1 or segment-register SPRs. The structured refill is a normalized result of software having found and validated a PTE. There are no reserved raw PTE bits on this interface; all provided field encodings are representable. The caller must have established PTE reference state before refill. C and WIMG are not invented or silently repaired.

A lookup reports `invalid_input` for an instruction write. T=1 then reports `direct_store_unsupported`, and an instruction lookup with N=1 reports `no_execute`, before any tag lookup. No tag match returns `miss`. A unique hit returns the matched way, WIMG, PP, C and implicit R=1 even if access is denied. Successful lookup alone sets `allow`; PA is zero for every denied or unfinished translation. A returned WIMG value is metadata, not evidence that a downstream cache honors it.

Page permissions are the following literal PEM table, unlike BAT protection:

| Selected key | PP=00 | PP=01 | PP=10 | PP=11 |
| --- | --- | --- | --- | --- |
| 0 | read/write | read/write | read/write | read only |
| 1 | no access | read only | read/write | read only |

The key is selected from current request PR/Ks/Kp, not cached at refill. N is ignored for data. On a unique hit, diagnostics choose PP denial first, then guarded instruction access (WIMG.G), then a permitted data write needing C update. This is a deterministic local classification when multiple conditions coexist, **not** a claim about exact architectural exception arbitration. Other WIMG bits pass through; no instruction-cache attribute enforcement is implemented here.

## R/C, collisions and explicit local policies

Every valid entry reports R=1, following the 603e's effective referenced-state description. There is no TLB R=0 encoding, PTE memory write, or automatic reference-clear operation. A permitted store hit with C=0 reports `hit=1`, `needs_changed=1`, `allow=0`, PA=0. Repeated attempts retain C=0. The caller performs the required software/PTE update and refills C=1 before retrying. Loads do not require C=1, and a protection-denied store does not request a C update.

The UM describes internal C update and table-search effects together and identifies a data-store TLB miss exception for this case. This service deliberately exposes the work still required at that boundary; it does not pretend to reproduce the internal moment C changes, synthesize the miss exception, or implement Figure 5-17's memory writes. The caller must invalidate stale cached translations after changing page mappings, permissions, or clearing PTE R/C. Memory coherence, atomics used by a page-table handler, speculation and exceptional/string/cache operations remain outside the interface.

A refill matching the same VSID/page tag in the other way is rejected atomically with `refill_rejected`; all prior entries remain intact. Replacing the selected way, whether matching or changing its old tag/RPN, is allowed. This is a local unambiguous-bank policy, not an invented silicon winner for duplicate translations. A defensive duplicate lookup reports invalid input with no PA, although the public refill interface cannot create that state.

Reset synchronously clears validity, the response slot, any runtime invalidate proposal and its acknowledgment; entry tag/data storage is not reset. Request-ready and response-valid are also combinationally gated by reset. This deterministic empty-bank reset is a **local initialization policy**, explicitly different from silicon. There is no `tlbia` command: to invalidate every stored translation without reset, send 32 indexed invalidations. Reset or an accepted invalidate cannot retroactively retract a response already delivered to a caller; any integration must arrange its own precise cancellation boundary.

## Build and validation

From the repository root:

```sh
verilator --lint-only -Wall --top-module ppc_tlb_service rtl/ppc_tlb_service.sv
verilator --binary --timing --assert -Wall --top-module tb_tlb_service \
  rtl/ppc_tlb_service.sv tb/tb_tlb_service.sv \
  --Mdir build/ppc-r39-tlb-service
build/ppc-r39-tlb-service/Vtb_tlb_service
```

`rtl/tlb_service_files.f` is a simulation-directory-relative standalone file list. The direct bench checks both ways in every set of both banks, segment aliases and VSID changes, extra tag bits, duplicate rejection and selected-way remapping, targeted invalidation with neighboring entries retained, all page permission/key/privilege combinations, C update retries and denied stores, N/T/G conditions, privileged management rejection, unsupported commands, held snapshots, simultaneous response-consume/request-accept, and reset with a held response and offered refill. The permission expectation is a literal table, independent of the RTL's Boolean equation. Physical-address expectations use arithmetic and fixed anchors.

Historical standalone Verilator 5.020 strict lint/build and runtime results for kinds 0–3:

- Direct corpus: **866 transactions / 3,528 checks PASS**.
- Parent-owned `sim/tools/tlb_vectors.py` corpus: **17,364 transactions / 902,705 checks PASS**, including all 128 entries, every bank/key/PP/WIMG/C combination, indexed invalidation, segment/VSID aliases, duplicates and deterministic mixed traffic. The oracle uses a virtual-page dictionary and arithmetic address decomposition; it does not read RTL. Its five literal-anchor Python tests are owned and run by the parent. All twelve response outcome flags occur in its corpus. Canonical integration may regenerate the corpus in `sim/build/tlb-service/vectors.txt`.
- **Nine negative gates PASS**: a deliberately corrupted expected response is caught by the actual RTL response comparator; empty, short, extra-token, nonhex, oversized-request, oversized-response, arbitrarily huge request and stall=33 inputs reject.

The independent run exposed an end-of-file handling bug in the first bench parser after every actual response had matched. The final line/token parser removes that ambiguity and was rerun against the complete corpus and all negative gates. No TLB RTL correction was required by the corpus. No synthesis, fitting or full-CPU/MMU conformance result is claimed.

## Optional external vector protocol

The existing standalone vector corpus retains its historical two-bit kind packing for kinds 0–3 even though the RTL ports are now three bits wide. The bench zero-extends vector request kinds and compares the original two-bit response kind field; kind 4 is covered by the separate runtime bench. Run the standalone executable with `+VECTORS=/absolute/path/vectors.txt`. Each nonempty record contains exactly three hexadecimal fields: **request93 stall_cycles expected90**. No comments or headers. Stall is 0..32; out-of-range bit widths, malformed and empty corpora reject. Vector mode starts from an empty reset service and runs instead of the direct corpus. It offers the following request during the current response stall, checks response stability and request blocking, then accepts the following transaction on the response-consumption edge. Expected responses are supplied by the external producer, not recomputed from RTL state.

Request packing (MSB first):

```text
92:91 kind       90 bank        89:58 EA       57:34 VSID
33 PR           32 Ks          31 Kp          30 N
29 T            28 write       27 way         26:7 RPN
6 C             5:2 WIMG        1:0 PP
```

Response packing (MSB first):

```text
89:88 kind      87 bank        86:55 EA
54 allow        53 hit         52 miss        51 PPfault
50 Gfault       49 Nfault      48 Tunsupported 47 needsC
46 privileged   45 refillRejected 44 unsupported 43 invalidInput
42:41 matched   40 way         39:8 PA        7:4 WIMG
3:2 PP           1 C            0 R
```

Non-lookup responses have only echoes and, when appropriate, one error flag. Early lookup input/T/N/miss diagnostics have no entry metadata. A hit includes entry metadata, even when its PA is suppressed. `matched=01` selects way 0; `10` selects way 1.

## Prepared refill extension

The opt-in `ENABLE_RUNTIME_REFILL` kind-5 path snapshots a normalized refill
and shares the existing commit/abort/ack reservation with kind-4 invalidation.
Kind-1 external refill remains immediate. See
[TLB_PREPARED_REFILL.md](TLB_PREPARED_REFILL.md) and
[verification](TLB_PREPARED_REFILL_VERIFICATION.md). Reset discards either
proposal and clears local valid bits under the existing initialization policy.
This service extension alone does not enable CPU TLB-load instructions.
