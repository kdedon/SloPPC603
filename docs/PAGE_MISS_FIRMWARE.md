# Compiled page miss result acceptance

The `page-miss` profile reuses the CPU TLB-load/invalidate workload with a
conditional final store probe. It builds a separate ELF from
`toolchain/tlbload-smoke.c` with `PAGE_MISS_STORE_PROBE`, and shares the fixed
bootstrap, interrupt handlers, linker layout and page/load probes. The new
store probe resides at `fff07008`; the ELF loader validates that symbol before
simulation. The original `tlbload` profile retains its original three modes.

All mappings are installed by CPU BAT, segment and TLB-load instructions;
external normalized management remains inactive. After translated I/D hits,
segment switching, external/decrementer interrupt return and two indexed
invalidations, the new profile exercises three terminal diagnostics:

| Mode | Access | Retired PC | Captured EA | Captured SR |
| --- | --- | --- | --- | --- |
| 0 | Data load miss | `fff07000` | `10008000` | `00001234` |
| 1 | Instruction miss | `20008000` | `20008000` | `00005678` |
| 2 | Data store miss | `fff07008` | `10008000` | `00002345` |

The strict harness requires exactly one illegal diagnostic retirement with
`FETCH_PAGE_MISS` or `DATA_PAGE_MISS`, PR=0, IR=DR=1 and write set only for the
store. It checks the entire EA/SR/context record, exact PC and data opcode,
zero destination/update/flag permissions, and zero miss metadata on every
ordinary retirement. Both physical data words remain unchanged after the
miss; the denied store cannot reach memory. Existing page effects, CPU TLB
loads, both interrupts, invalidation and the success-mailbox retirement are
required before the terminal miss. A mailbox write alone is not success.

Focused strict acceptance on 2026-09-23:

| Mode | Retirements | Cycles | Physical reads / writes |
| --- | ---: | ---: | ---: |
| 0 | 443 | 5,253 | 27 / 45 |
| 1 | 443 | 5,240 | 27 / 45 |
| 2 | 449 | 5,335 | 27 / 45 |

Each mode has four CPU TLB loads, two TLBIE operations, eight successful
instruction-page retirements, one external interrupt and one decrementer
interrupt.
An isolated RTL copy that replaces the captured segment descriptor with zero
is rejected in mode 0 at cycle 5,246 with “retired miss snapshot differs from
access context.” The canonical sources and ELF were unchanged by this negative
control.

Build with `make page-miss` in the pinned offline cross-toolchain container,
then run from the repository root:

```sh
python3 toolchain/run-rtl-smoke.py --profile page-miss \
  --elf toolchain/build/page-miss/smoke.elf \
  --build-dir toolchain/build/rtl-page-miss
```

This workload proves precise diagnostic capture, not architectural miss entry
or software refill/retry. C=0-store classification and cancellation are covered
by the independent directed tests in [PAGE_MISS_RESULT_VERIFICATION.md](PAGE_MISS_RESULT_VERIFICATION.md).
TGPR, miss SPR/hash state, miss vectors and page-table R/C handling remain open.
