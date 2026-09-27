# Page-hit data protection DSI verification

Recorded: `make -C sim lint-page-data-exceptions test-page-data-exception-router test-core-page-data-exception`, commit pre-repository snapshot, imported in 3e727b6, 2026-09-23.
Recorded: `make -C sim test-page-data-exception-router test-core-page-data-exception`, commit cf05f65, 2026-09-27.

## Direct-store segments, 2026-09-27

Pass. The router bench reports **275 checks** in both the enabled and
disabled profiles; the actual-core bench reports **1,637 checks** with the
micro-TLB and **1,806** without it. The router bench now preloads an allowed
DTLB entry for the same VSID and page, sets SR.T=1, and requires a held
`DATA_DSI_DIRECT_STORE` response (enabled) or the generic error plus sticky
`page_direct_store_o` (disabled) for both a load and a store, with no
physical offer. The core bench adds two phases: `lwzu` and `stwu` through an
SR.T=1 segment over an allowed TLB entry. The handler reads DAR=`0x10001234`,
DSISR=`0x04000000` (load) or `0x06000000` (store), SRR0=`32` and SRR1=`0x10`,
skips the access and returns; destination, base and memory are unchanged and
no sticky diagnostic is set. The compiled MMU stress image repeats both cases
on the translated cached 60x top ([MMU_STRESS_FIRMWARE.md](MMU_STRESS_FIRMWARE.md)).

## Page PP denial, 2026-09-23

The opt-in `ENABLE_PAGE_DATA_EXCEPTIONS` profile delivers a clean page-TLB PP denial through the existing precise `DATA_DSI_PROTECTION` response. It requires page translation and data exceptions; the ordinary profile retains diagnostic page failures. TLB misses, C=0 stores, malformed/provenance errors and conflicting causes remained diagnostics; direct-store segments were added on 2026-09-27 (above).

The focused strict gate `make -C sim lint-page-data-exceptions test-page-data-exception-router test-core-page-data-exception` passes (2026-09-23). The independent router bench reports **228 checks in each enabled and disabled profile**. It preloads real DTLB entries and checks Ks/PP and Kp/PP read denial, PP store denial ahead of C-bit work, held response stability, CSR/context/management exclusion, captured EA/access kind, no physical offer, and default-off `DATA_OK` plus legacy error. Miss, C=0 and SR.T cases never become typed protection. Adversarial service responses with a wrong kind or simultaneous protection and guarded flags also stay generic diagnostics.

The actual-core wrapper bench reports **1,132 checks**. Literal update-form load and store programs enter the DSI handler from a page-hit PP denial. Six retirement-stall cycles leave DAR/DSISR unchanged. Handler MFSPR reads confirm DAR=`0x10001234`, DSISR protection=`0x08000000` plus store=`0x02000000`, faulting SRR0=`32`, and old MSR.DR in SRR1. The handler skips the denied instruction and returns with RFI. Neither load destination nor update base changes; denied stores make no physical data offer. An external cut accepted on the typed response suppresses DSI state, handler execution and GPR changes.

The legacy page router, BAT data fault and core data-fault cancellation tests remain separate regressions. A compiled CPU program additionally checks TLBLD repair and RFI retry, owned by the integration lane. These checks do not claim architectural TLB-miss entry or C-bit refill handling.
