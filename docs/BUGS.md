# Suspected bugs

Reports of possible CPU or system faults, how each was investigated, and the
outcome. Open entries say what would settle them.

## BUG-01: Dhrystone `Int_2_Loc` mismatch on the native-video MiSTer build

Status: likely explained by BUG-02; closed unless it recurs with the
BUG-02 fix.

BUG-02 is a write under reset that corrupts one random doubleword of the
loaded image in some Verilator X-random models. A changed instruction or
data word that stays legal gives exactly this signature: one wrong result,
deterministic for one model, gone after any change that reshuffles the
random initial values. The original run's RTL is lost, so this is not
proven.

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

## BUG-02: illegal-instruction exception on a legal `mr` in the MiSTer DDR3 build

Status: fixed. A write to SoC RAM before the first reset edge corrupted the
loaded image. SoC bench fault; the CPU is not involved.

### Report

After the MiSTer framebuffer core merged onto the performance-counter round,
`mister-smoke` (DDR3 build, `+verilator+seed+1 +verilator+rand+reset+2`)
exits with `e0000700` at 959,714 cycles, 114,470 retirements, during hello's
Mandelbrot. The exception is taken at cycle 625,534 with SRR0 `fff03e44`
and SRR1 `00080070`: SRR1[12], illegal instruction. The image holds
`7e549378` (`mr r20,r18`) there.

### Cause

`soc_bus60x_target` drove its beat port from registers that reset
synchronously: `req_o`/`we_o` were `write_q && !ta_n_o`. Until the first
reset edge those registers hold the simulator's initial values, and the
SoC RAM has no reset, so the first clock edge under reset could write one
doubleword. With seed 1 the model starts with `write_q=1`, `ta_n_o=0`,
`wr_addr_q` ending in `0x3e40`, `addr_q[2:0]=4` and `tsiz_q=5`: the edge
writes bytes 4-7 of RAM doubleword `0x03e40`, the `mr` at `fff03e44`, after
`$readmemh` loaded it. Fetch, cache and decode then handled the corrupted
word correctly.

On hardware the registers power up at zero, so this needs reset asserted
during a beat; the fault is mainly one of simulation, but reset now blocks
the side effect either way.

### How it was found

Instrumenting the model (displays, FST tracing, ring buffers) shifts
Verilator's random initial values, and every instrumented model passed. The
unmodified model was bisected instead: in the generated
`___ctor_var_reset`, a range of assignments was zeroed while each random
draw was kept, so the other variables kept their values. Eleven rebuilds
of that one file isolated `soc.target.write_q`; zeroing it alone makes
seed 1 pass.

### Fix

`req_o` and the write beat are qualified with `rst_ni` in
`rtl/soc/soc_bus60x_target.sv`, so the target requests no read or write
beat while reset is asserted. The benches' console output is also ignored
before the first reset edge (the stray first character in some seeds).

`test-soc-target-reset` (`tb/soc/tb_soc_target_reset.sv`, in `test`)
checks that no beat is requested before the first edge, or after reset
arrives during a write beat or a read beat. On the unfixed target it fails
3 of 13 checks; with the fix it passes.

### Guard

`make -C sim -j2 xrand-sweep` reruns the SoC target, core full-decode,
chip pins, demo hello and MiSTer hello (DDR3 and native) benches with X
seeds 1-8 plus all-zero and all-one initial state (60 runs); each model
builds once. It belongs in the batch gate next to `ci`.

### Checks

Recorded: `make -C sim mister-smoke`, commit 19606f4, 2026-09-29. Fails as
reported (`exit=e0000700 cycles=959714 retired=114470`).

Recorded: `make -C sim test-soc-target-reset`, commit 19606f4 plus the fix
in this entry, 2026-09-29. PASS, 13 checks; with the target reverted to
19606f4 it fails 3 of 13.

Not yet recorded: `mister-smoke` seed 1 with the fix, and a complete
`xrand-sweep`. The first sweep run passed its soc-target-reset, core
full-decode and chip-pins runs (30 of 60) and stopped on `demo-hello` seed 2
at `DE is not the complement of the blanks`, a bench check sampling video
outputs before reset; the bench now checks only out of reset.
