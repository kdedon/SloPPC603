# Compiled page-protection DSI acceptance

The `page-dsi` profile runs a single big-endian PowerPC ELF against the integrated CPU, BAT router, segment registers, and TLB service. The new `ENABLE_PAGE_DATA_EXCEPTIONS` parameter is opt-in. The fixture never issues normalized TLB management requests or programs BATs; CPU instructions install both the bootstrap BAT and each DTLB entry. The program runs with instruction translation off, enables data translation for each protected access, and uses a high-prefix DSI handler at `fff00300`.

The program selects segment 1 with VSID `001234` and supervisor key Ks=1. It first installs a way-0 page entry for EA `10008000` to physical `fff08000` with PP=00, C=1. Its update-form load is denied. The handler records DAR, DSISR, SRR0, SRR1 and entry MSR, observes the unchanged physical word, writes RPA with PP=10, executes `tlbld` in real mode, and returns with `rfi` to retry the load. Software then reinstalls the same entry with PP=01; the update-form store is denied under Ks=1. The handler repairs it with PP=10 and retries. Both cases require the original faulting PC in SRR0, DAR=`10008000`, DSISR protection bit, the store bit only for the store, saved MSR=`00000050`, and entry MSR=`00000040`.

The independent physical RAM responder delays instruction/data responses and retirement. At each fault retirement it checks that no GPR, update base, or XER write is authorized. It also directly reads the faulting update base and load destination from the core register file before retirement, proving that the denied load has not altered either. Only the initialization store and the retried permitted store may reach the protected physical word; the handler's direct physical read confirms it is unchanged before repair. The test requires the two DSI retirements, four CPU `tlbld` retirements (two setup and two repairs), 12 CPU BAT writes, eight DR transitions, clean page-protection diagnostics without miss/configuration/guarded/changed causes, and a success mailbox. This proves page PP denial can use the existing precise DSI carrier; it does not implement automatic page-table walking or TLB-miss exception entry.

Build with the pinned container toolchain, then run the strict Verilator profile:

```sh
docker run --rm --user "$(id -u):$(id -g)" --volume "$PWD:/work" --workdir /work/toolchain ppc603e-cross:bookworm-20250811 make page-dsi
python3 toolchain/run-rtl-smoke.py --profile page-dsi --elf toolchain/build/page-dsi/smoke.elf --build-dir toolchain/build/rtl-page-dsi
```

Initial integrated acceptance on 2026-09-23: **2 page DSIs, 4 CPU TLB loads, 12 CPU BAT writes, 384 retirements, 4,532 cycles**. The prior BAT DSI and page-hit firmware profiles remain separate regression gates.
