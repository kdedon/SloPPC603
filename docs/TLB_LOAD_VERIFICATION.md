# CPU TLB load verification

The opt-in `ENABLE_TLB_LOAD` path executes 603e `tlbld rB` and `tlbli rB` through a captured, retirement-owned prepared refill. This verification covers the bounded software-seeded profile; architectural page-miss entry and software miss-handler sequencing are separate work.

`make -C sim lint-tlb-seed lint-tlb-load-integration test-tlb-load-decode test-core-tlb-load test-tlb-runtime-fill-router` passed with strict Verilator warnings and assertions on 2026-09-23. The decoder oracle passed **12,366 checks**. It anchors real `-mcpu=603e` object-dump words (`7c00ffa4`, `7c003fe4`, `7c004fe4`), tests all 32 old rB fields for both opcodes, and rejects 4,032 reserved RT/RA/Rc combinations. Default-off and baseline profiles reject both opcodes; combined BAT, segment, and TLBIE options leave the decode unchanged.

The direct actual-core oracle passed **2,812 enabled** and **26 default-off** checks. Literal programs seed DCMP, ICMP, RPA and SRR1.WAY using CPU instructions, then observe both fill banks. They verify full old r31 and r0 EA values, separate compare VSIDs, selected way 0 and 1, RPA RPN/C/WIMG/PP fields, stable held offers, and no early entry mutation during an eight-cycle retirement hold. A minimal external service model records the accepted proposal and exposes the entry only on the matching retirement commit; its response and commit acknowledgment can be delayed. The bench cuts a held offer, a same-edge accepted offer, a held response, and a same-edge result; it checks abort/drain and no killed retirement. Two retained redirects during a held offer select the latest target after delayed acknowledgment. A service error with a still-owned proposal must abort and reach idle before reset. Reset during a held acknowledgment permits fresh two-bank reuse.

Five malformed local seed cases (compare V=0, H=1, API mismatch, and either reserved RPA field) and translated MSR.DR execution each produce a diagnostic without any fill offer. Both opcodes in problem state enter Program Priv with SRR0/SRR1 evidence and no offer. Disabled-feature execution retains the illegal diagnostic. The separate direct router bench passed **1,211 enabled** and **4 disabled** checks, including all 32 sets, both banks and ways, management exclusion and ownership/cancellation. The router bench is owned and specified in [`TLB_LOAD_PROTOCOL.md`](TLB_LOAD_PROTOCOL.md); this file records its result as part of the focused gate.

All 45 legacy direct `ppc_core`/`ppc_special` fixtures received inactive fill-port tieoffs. The combined page-profile and standalone core lint targets pass; production wrappers and compiled firmware have their own integration gates.

## Integrated acceptance

The parent accepted `make -C sim -j6 regression` with exit 0 on the frozen
round-3 inputs. The gate includes 243 Python checks; all 177 distinct strict
testbench lint configurations also pass. All twelve compiled workload profiles
pass, with three modes each for TLBIE and CPU TLB loads. A missing-first-load
negative fails at the first page use; see [TLB_LOAD_FIRMWARE.md](TLB_LOAD_FIRMWARE.md).
Forty-eight recorded production inputs and 284 final source/configuration inputs
were unchanged at acceptance.
No FPGA fit or architectural miss-handler acceptance was performed.
