# Prepared TLB refill verification

`make -C sim test-tlb-prepared-refill` builds `tb_tlb_prepared_refill.sv` with strict `-Wall --assert` in every `ENABLE_RUNTIME_INVALIDATE` / `ENABLE_RUNTIME_REFILL` combination. All four profiles pass:

| Invalidate | Refill | Checks |
| --- | --- | ---: |
| 0 | 0 | 156 |
| 0 | 1 | 268 |
| 1 | 0 | 158 |
| 1 | 1 | 280 |

The bench uses only public service pins and literal expected physical addresses, WIMG, PP, and C values. It preloads both TLB banks and ways, verifies the existing immediate refill and lookup kinds, and checks that kind 5 is unsupported when disabled. With refill enabled, privilege rejection wins over an opposite-way duplicate; the same duplicate is rejected when privileged mode is clear. A successful proposal reserves one slot until abort or commit, and a held response cannot change when all live caller fields change. Aborting while the response is held leaves the previous mapping intact. A successful proposal commits after every live input field is changed, including kind, bank, set, way, VSID, RPN, C, WIMG, and PP; only the original bank/set/way/tag/attributes become visible. Response consumption and commit are also tested on the same edge, with a held acknowledgement blocking further requests.

Further checks cover independent bank/way replacement, neighboring-set isolation, abort on the acceptance edge, kind-4/kind-5 shared reservation exclusion, reset with a prepared response or commit acknowledgement pending, and unchanged immediate kind-2 invalidation. Public lookups after abort and commit establish the visible state; the oracle does not read DUT entry arrays.

Compatibility gates also pass after the kind-5 extension: the standalone TLB service suite reports **866 transactions / 4,415 checks**, its independent legacy-vector run reports **17,364 transactions / 1,197,818 checks**, and the runtime-invalidate service reports **96 checks**. The vector file's existing 93-bit request and 90-bit response format remains unchanged. As a negative control, an isolated mutant that wrote the live refill input at commit instead of the captured proposal compiled successfully but failed this bench at public lookup check 151; see `/tmp/ppc-refill-live-mutant-build.log` and `/tmp/ppc-refill-live-mutant-run.log`.

This service boundary does not add a CPU refill instruction or page-table walker. Architectural TLB load instructions and software register programming are separate slices.
