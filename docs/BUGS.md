# Suspected bugs

Reports of possible CPU or system faults, how each was investigated, and the
outcome. Open entries say what would settle them.

## BUG-01: Dhrystone `Int_2_Loc` mismatch on the native-video MiSTer build

Status: not reproduced; no CPU fault found. Open until it recurs.

### Report

While the 1080p framebuffer (64e7929) was in development, one
`make -C sim mister-smoke MISTER_FB=0` run with the firmware as at 43da8cf
failed Dhrystone with exactly one mismatch: the `Int_2_Loc` line printed a
wrong value. The RTL of that run was an uncommitted intermediate state; with
the 64e7929 firmware the same configuration passes.

### Firmware analysis

In the 43da8cf image (`dhry_main`, `-O2`) `Int_2_Loc` never reaches memory.
After the loop's final, mispredicted `bge` it is computed into r20:

```
fff03a60  mulli r28,r28,3          Int_2_Loc * Int_1_Loc
fff03a64  lwz   r9,76(r1)          Int_3_Loc
fff03a6c  divw  r10,r28,r9         Int_1_Loc
...
fff03a94  subf  r9,r9,r28
fff03a9c  mulli r9,r9,7
fff03aa4  subf  r20,r10,r9         Int_2_Loc = 7 * (Int_2_Loc - Int_3_Loc) - Int_1_Loc
```

It stays in r20 across `times` and twelve `dhry_printf` calls, and is printed
with `mr r4,r20` at fff03d28. None of those callees (`vprintf`, `format`,
`con_putc`, the framebuffer and register helpers) saves or uses r20; only
`hello_main`, `dhry_main` and CoreMark functions do. Inside the loop r20 holds
a pointer (0xfff128a0), so a lost `subf r20` result would print -977760.

The inputs rule out a memory cause for a lone mismatch: a wrong `Int_3_Loc`
load or `divw` result would also change `Int_1_Loc` (the inlined `Proc_2`
derives it from r10) or `Int_3_Loc`, which matched. The layout is clean: code
ends at 0xfff09238, `.data`/`.bss` run 0xfff10000-0xfff12900, the heap ends
at 0xfff17c00, the 32 KiB stack sits at the top of the 128 KiB RAM, and the
framebuffer (0xf0000000) and registers (0xf0100000) are outside it. `printf`
has no buffer; BSS is cleared by `crt0`. A firmware cause is therefore
unlikely: a lone wrong `Int_2_Loc` points at the `subf`/`mulli`/`subf r20`
chain or at r20's rename state after the loop-exit recovery.

The 43da8cf firmware writes its framebuffer at the fixed 0xf0000000 through a
2 MiB DBAT1. On the 64e7929 core (framebuffer at 0xf0200000) its first
framebuffer store is unclaimed and the run checkstops, so the failing run
cannot have used the 64e7929 map; the checks below place the framebuffer at
0xf0000000 (`MISTER_FB_BASE=f0000000`).

### Checks

Old image: `git worktree add --detach <dir> 43da8cf`, then in `<dir>`
`toolchain/demo/fetch-benchmarks.sh` and
`toolchain/build-in-container.sh -f demo/Makefile mister all`; runs use
`DEMO_FW_DIR=<dir>/toolchain/build/demo DEMO_FW_MAKE=true`.

Recorded: `make -C sim mister-smoke MISTER_FB=0` (64e7929 firmware), commit 64e7929, 2026-09-29.
PASS, 23 checks, 0 mismatches; 42,687,368 cycles, 11,449,786 retired.

Recorded: `make -C sim mister-smoke MISTER_FB=0 MISTER_FB_BASE=f0000000` and
`make -C sim mister-smoke MISTER_FB=1 MISTER_FB_BASE=f0000000 XRAND_SEED=2`,
43da8cf image, commit 64e7929 plus the bench changes in this entry, 2026-09-29.
Run all (`MISTER_MODE=03`): both PASS with 0 of 23 mismatches (`Int_2_Loc:
13`). Native 45,202,568 cycles, 14,584,050 retired; DDR3 44,329,735 cycles,
14,487,069 retired, 153 sectors saved. `MISTER_MODE=01` on the same models
also passes (native 4,120,968 cycles).

Recorded: `make -C sim demo-soc-model`, then `sim/build/demo/model/Vtb_demo_soc
+verilator+seed+1 +verilator+rand+reset+2` with the 43da8cf `dhrystone.hex`
(2000 runs), commit 64e7929, 2026-09-29. PASS, 0 mismatches, 8,212,205 cycles.

Exploratory sweeps (scratch scripts, not make targets), commit 64e7929,
2026-09-29. The image was relinked with the 43da8cf objects and a
`mister.ld` changed only to add `TPAD` to the `.text` address, `DPAD` to the
`.data` address and to lower `__stack_top` by `SPAD`:

- `MISTER_MODE=01`, native and DDR3 models built as with
  `MISTER_FB_BASE=f0000000 XRAND=0`, 54 layouts each: `TPAD` 0-124 in
  steps of 4 plus 256, 512, 1024 and 2048 (every word offset within and
  across I-cache lines; Dhrystone took 687,066-687,228 cycles), `DPAD` 8-64
  in steps of 8 plus 4096, and `SPAD` 8-64 in steps of 8 plus 1024. 108 of
  108 pass with 0 mismatches.
- `MISTER_MODE=03`, native, X seed 1, `TPAD` 4-28 and 1024, `DPAD` 8,
  `SPAD` 8: all pass with 0 mismatches.
- `MISTER_MODE=03`, native and DDR3, X seeds 2-7 (`+verilator+seed+N`) with a
  different DDRAM busy pattern per seed (the `MISTER_BUSY_SEED` effect):
  every Dhrystone run reports 0 of 23 mismatches. The busy pattern barely
  reaches the core (DDR3 totals differ by under 100 cycles), and X seeds do
  not change the native cycle count, so these add little timing variety.

What this establishes: the reported mismatch does not occur on the 64e7929
core with the 43da8cf image across code, data and stack placement, cache-line
alignment, X initial state and DDRAM back-pressure. What it does not: the
intermediate RTL of the original run was never committed and cannot be
rerun, so a fault in that state (SoC or CPU) is not excluded, and no
reference trace was compared for the Dhrystone region.

Next step if it recurs: keep the RTL tree and image, rerun with `+TRACE`,
and diff the retirement trace from the loop-exit `bge` at fff03a90 to the
print at fff03d28; a directed bench would put a `divw` ahead of a
mispredicted loop branch followed by back-to-back writes of one register
(`subf r9`, `mulli r9`) and a consumer (`subf r20`) of both.

### Bench fault found on the way

With X seeds other than 1, the DDR3 build failed after the firmware passed:
`save did not end once`. `save_done_o` is undefined until the first reset
edge and the bench counted it during reset. The bench now counts saves only
out of reset; the RTL is unchanged. The same DDR3 configuration with X seed 2
failed this way before the change; the `XRAND_SEED=2` run above passes.
