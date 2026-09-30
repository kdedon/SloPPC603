# FPU core integration verification

Evidence for [FPU core integration](FPU_CORE_INTEGRATION.md).

Recorded: `make -C sim -j2 lint check-spec test-core-fpu test-chip-fpu`, commit `a6f9b73`, 2026-09-30.

All passed. Lint now also covers `ppc_core` with `ENABLE_FPU=1` and the
`ppc603e` pin top with `ENABLE_FPU=1`.

| Bench | Result |
| --- | --- |
| `test-core-fpu`, retirement stalls (`+STALL=1`) | 1455 checked words; 6583 retirements, 2359 FP; 69 exceptions; 41060 cycles |
| `test-core-fpu`, no stalls (`+STALL=0`) | 1455 words and 24 latency probes; 38543 cycles |
| `test-chip-fpu` | self-check of 397 words (every nonzero mask) with 18 exceptions; 76133 cycles, 102 read bursts |

`test-core-fpu` runs `ppc_core` (supervisor, live context, full decode, FPU)
on one word-addressed memory with a protected DSI window, one program from
`sim/tools/fpu_core_program.py` (seed `0x603e`, 200 random cases) and exception
handlers that log SRR0, SRR1, DAR, DSISR and the vector. It establishes:

- Illegal forms before FP unavailable with MSR[FP]=0 (`fadd` with a nonzero
  frC field, `fsqrt`); FP unavailable on `lfd`, whose handler sets MSR[FP] in
  SRR1 and retries it.
- Every load and store form: `lfs`, `lfsu`, `lfsx`, `lfsux`, `lfd`, `lfdu`,
  `lfdx`, `lfdux`, `stfs`, `stfsu`, `stfsx`, `stfsux`, `stfd`, `stfdu`,
  `stfdx`, `stfdux`, `stfiwx`, with update-form base values and a word-aligned
  doubleword.
- `fmr`, `fneg`, `fabs`, `fnabs` on an SNaN and −0 with Rc=1 (CR1); `fsel`
  for ±0, negative, NaN and +∞ selectors; `fcmpu`/`fcmpo` into four CR fields
  with FPCC, VXSNAN and VXVC; `mcrfs`; `mtfsfi.`, `mtfsf.` with a field mask,
  `mtfsb0.`, `mtfsb1`; `fres`/`frsqrte` special operands (FR/FI masked as
  undefined).
- Alignment on `lfd`, `stfdu` and `lfdx` with DAR, DSISR, unchanged FPR and
  base; DSI on a load, a store (store bit) and an `lfdu` whose second word
  faults (DAR = EA+4, base unchanged).
- FP enabled program exception from `mtfsb1` with FE0/FE1 set: SRR1 bit 11,
  FPSCR update committed.
- 200 random arithmetic cases from `sim/fpu/enabled_vectors.py` (`fadd` …
  `fnmadd` single and double, `frsp`, `fctiw`, `fctiwz`) with random
  VE/OE/UE/ZE/XE, NI, RN, FE0/FE1 and Rc: FPR result or preserved sentinel,
  FPSCR (FR masked after disabled overflow), CR, and the program exception
  whenever `(FE0∨FE1)∧FEX`. Expectations come from the Python reference
  model, not from the RTL.
- Random retirement backpressure (one cycle in four), which also delays store
  authorization at the queue head.
- The dispatch-to-retirement latencies in the contract table, exact to the
  cycle without stalls.

`test-chip-fpu` runs a self-checking build of the same generator (40 random
cases, no DSI section) on the `ppc603e` pin top from the hard reset vector
with HID0[DCE] set, against the coherent 60x target with random wait states,
ARTRY and DRTRY. It establishes that FP loads and stores through the data
cache and 60x bus produce the same results and exceptions; a program with one
corrupted expectation fails through the mailbox.

A second seed also passed on commit `8b46d53`:
`make -C sim test-core-fpu FPU_CORE_SEED=0x51ed FPU_CORE_RANDOM=500` checked
3240 words with 126 exceptions and 5659 FP retirements.

Unchanged behavior with `ENABLE_FPU=0` was checked on commit `135267a`, the
integration commit, with `make -C sim -j2 test-core test-crstate-execution
test-exception-state test-decode-sweep test-core-full-decode
variant-full-decode-0 variant-full-decode-1 variant-full-decode-2
variant-full-decode-4 variant-watchdog-602 variant-special-lint-602
test-core-alignment test-core-data-fault test-core-control-memory
test-core-lsu-update test-core-cache-control variant-icache-602`: all passed,
including FP unavailable in `tb_core_full_decode` (8669 checks, 70 events).

Not established: overlap or Table 6-5 throughput (the lane is serialized by
design); TLB miss, page-changed and machine-check faults on FP accesses;
recovery cancelling an FP instruction; compiled FP firmware (no PowerPC
cross-compiler or toolchain container on the build machine); fitted area and
timing with the FPU in the core.
