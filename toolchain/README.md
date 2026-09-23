# PowerPC bootstrap toolchain

This directory builds one freestanding smoke program as 32-bit PowerPC ELF in
both byte orders. The BE program also runs through the supervisor-enabled cached 60x RTL wrapper
with an independent bus RAM responder. The compiler uses an integer/soft-float
profile; this smoke program does not exercise floating-point operations.

## Reproducible container build

The container pins the dated Debian base by registry digest and uses a Debian
snapshot with exact package versions. Snapshot metadata and packages are
authenticated by APT signatures; HTTP avoids depending on CA state in the bare
bootstrap image. `build-container.sh` records the resulting local image ID and
any registry digest alongside the artifacts.

Run these commands from `ppc603e/`.

```sh
./toolchain/build-container.sh
```

The script builds `ppc603e-cross:bookworm-20250811`, runs `make clean all check
repro`, and records compiler/binutils versions and artifact SHA-256 sums under
`toolchain/evidence/`. Set `TOOLCHAIN_IMAGE` to use an already-built image.

## Local smoke build

If `powerpc-linux-gnu-gcc` and its binutils are installed:

```sh
make -C toolchain all check
make -C toolchain repro
```

Override `CROSS` for another GNU prefix, for example
`make -C toolchain CROSS=powerpc-none-eabi- all check`. `make probe` never fails
for missing optional tools and is suitable for environment inventories.

Outputs are `build/{be,le}/smoke.{elf,bin,dump,map}`. The checker verifies:

- ELF32 PowerPC identity and BE/LE `EI_DATA` values;
- the first instruction word has bytes `60 00 00 00` for BE and
  `00 00 00 60` for LE;
- `_start`, `main`, and `tohost` appear in each disassembly/symbol table; and
- the two builds use the same entry address and keep `tohost` four-byte aligned.

`crt0.S` installs a small stack, calls `main`, stores its return value to
`tohost`, and loops. `link.ld` puts `_start` at the scaffold reset address
`0xfff00100`; all loadable content stays in the 64 KiB bootstrap window. A
`tohost` word of zero means running, one means pass, and `0x80000000 | test_id`
means failure. The RTL smoke harness observes this convention at the external bus RAM. It
checks for CPU/transport faults, completion timeout, and expected memory traffic,
and requires the mailbox store to retire and the transport to drain before passing.

The LE artifact proves compiler/assembler/linker byte order only. Architectural
LE instruction/data behavior remains P26 work and is not implied by this build.

## Compiled firmware execution

With the local cross-compiler and Verilator installed:

```sh
make -C toolchain rtl-smoke
```

If artifacts were built with the pinned container, run the harness on the host:

```sh
python3 toolchain/run-rtl-smoke.py --elf toolchain/build/be/smoke.elf
```

The runner validates the ELF identity, reset entry, physical load window and
`tohost` symbol, loads its segments into a 64 KiB BE RAM image, builds the
Verilator test, and requires a successful mailbox write. Instruction fetches use
four-beat cache refills; data uses scalar 60x transactions. Retirement experiences
periodic backpressure. Startup stack initialization, branches, loads, arithmetic,
comparison and function return execute from compiler/assembler output.

This is an optional gate because a cross-compiler is not required by the normal
simulation suite. Running with `--elf` uses that existing artifact without
rebuilding it. The test is a compiled-program baseline, not supervisor exception,
interrupt, page translation or arbitrary C/ABI coverage. Its bus responder
currently supports the word data accesses used by this program.

## Compiled alignment handler

```sh
make -C toolchain rtl-alignment
# Or compile `make alignment` in the pinned container, then on the host:
python3 toolchain/run-rtl-smoke.py --elf toolchain/build/alignment/smoke.elf --build-dir toolchain/build/rtl-alignment
```

This BE workload selects high exception vectors through the existing SRR/RFI
control path, then executes twelve pairs of deliberately misaligned LWZU and
STWU instructions. The handler at `0xfff00600` preserves its scratch registers
in SPRG0–2, records DAR/DSISR/SRR0/SRR1, advances SRR0 and returns with RFI. C
checks unchanged destination/base registers and data memory, exact exception
counts and saved state, and the manual-defined DSISR fields extracted from each
linked instruction. These checks tolerate compiler register allocation changes.

The workload tests the current aligned-access RTL profile's resumable fault
behavior. Real 603e hardware handles some ordinary unaligned accesses internally;
this workload does not establish full unaligned-access conformance. It exercises
skip recovery; independent RTL tests cover repairing an address and retrying.
The linker variant reserves the high alignment vector and rejects text overlap.

## Compiled firmware with synthetic fetch faults

`make fetch-fault` builds the big-endian `fetch-smoke.c` workload, ISI handler and
fixed-address probes. Build with the same pinned local cross-compiler container
as the other firmware profiles. Then run `make rtl-fetch-fault` on the host with
Verilator, or invoke:

```sh
python3 run-rtl-smoke.py --profile fetch-fault \
  --elf build/fetch-fault/smoke.elf --build-dir build/rtl-fetch-fault
```

This profile executes on the **abstract core**, not the physical bus/cache
wrapper. Its independent responder injects one synchronous protection cause at
`0xfff00800` and one guarded cause at `0xfff00900`, then supplies ordinary
instructions on retries. These are synthetic typed responses, not real MMU
translation faults, cache errors, TEA or machine checks. The runner verifies
that the ELF's two probe symbols and high ISI handler occupy their required
loaded addresses before simulation.

The compiled C program seeds DAR/DSISR, calls each probe, and checks returned
values, fault counts, saved PC/MSR and preservation of DAR/DSISR. The handler
preserves scratch registers with SPRGs and returns with RFI to retry the same PC.
A second call to each probe must succeed without another fault. Instruction and
data responses have variable latency; requests and retirement receive
backpressure. Success requires exactly two injected and retired fetch events,
`tohost=1`, and accepted retirement of the mailbox store. A nonzero failure
mailbox, unexpected diagnostic or timeout fails the run.

This is compiled-software acceptance of the typed exception carrier. It does
not establish production MMU, bus-fault, cache, interrupt or full-ISA acceptance.

## Compiled live BAT context

```sh
make -C toolchain live-context
python3 toolchain/run-rtl-smoke.py --profile live-context \
  --elf toolchain/build/live-context/smoke.elf \
  --build-dir toolchain/build/rtl-live-context
```

Compile in the pinned container when the cross-compiler is not installed on the
host. `make -C toolchain rtl-live-context` combines compilation and simulation.
The new profile uses the live-context BAT wrapper with variable-latency physical
word channels and retirement backpressure. The harness installs supervisor
128-KiB BAT entries before starting: instruction/data identity maps for
`0xfff00000`, plus a data alias from `0x10000000` to `0xfff00000`.

Compiled C enables IR/DR through MTMSR and ISYNC, checks MFMSR, writes and reads
the alias, and executes SC. The handler at `0xfff00c00` checks exception context
through recorded MFMSR/SRR1 values; RFI restores translation. Firmware then
disables translation and checks the same physical data. Code and stack mappings
remain identical across context transitions; this does not depend on changing
the instruction stream through an implicit branch. Success requires the final
mailbox store to retire and both physical channels to drain.

This exercises a real BAT translation producer and the committed context
handshake. BAT programming remains a harness startup operation. It does not
cover software BAT writes, page TLB refill, interrupts, data-fault recovery,
the physical 60x bus, or instruction-cache integration in this profile.

## Compiled external interrupts

```sh
make -C toolchain external-interrupt
python3 toolchain/run-rtl-smoke.py --profile external-interrupt \
  --elf toolchain/build/external-interrupt/smoke.elf \
  --build-dir toolchain/build/rtl-external-interrupt
```

Compile in the pinned container if needed; `rtl-external-interrupt` combines
build and simulation on hosts with the compiler. This profile enables supervisor,
live-context and external-interrupt support in the BAT wrapper. Its startup BAT
maps match the live-context workload above. The handler is linked at
`0xfff00500`; the runner validates its loaded address.

The harness holds the first IRQ while EE is masked. Firmware enables IR/DR,
then EE, and checks that the interrupt saves the address immediately after
MTMSR. The second IRQ starts during an accepted translated alias store with a
delayed response. It must wait for that store to retire and save the following
PC. Both returns check handler MSR, SRR0/SRR1, preserved DAR/DSISR and restored
translation. The handler preserves scratch GPRs in SPRGs and uses RFI without
modifying SRR0. No synthetic instruction retirement represents an IRQ.

Success requires exactly two interrupt acceptances, six IR/DR transitions,
exactly one alias store, a successful mailbox retirement and drained physical
channels. This tests synchronous level delivery; CDC belongs to the embedding
system. TB/DEC, page refill, data-fault recovery and combined cache/60x/MMU
integration remain outside this profile. See `docs/EXTERNAL_INTERRUPTS.md` and
`docs/COMPILED_FIRMWARE_VERIFICATION.md` for the bounded priority contract and
recorded positive/negative results.

## Compiled time base and decrementer

```sh
make -C toolchain timer
python3 toolchain/run-rtl-smoke.py --profile timer \
  --elf toolchain/build/timer/smoke.elf --build-dir toolchain/build/rtl-timer
```

Use the pinned container for compilation when needed; `rtl-timer` combines the
build and simulation. This profile enables timers, external interrupts and live
supervisor context in the BAT wrapper. The ELF reserves external vector
`0xfff00500`, DEC vector `0xfff00900`, and places main code at `0xfff01000`.
The linker guards both stack space and fixture words at `0xfff03000/3004`.

The program writes the time base, then reads TBU/TBL/TBU with retry. The fixture
enables TB after the first upper read while the lower half is `0xffffffff`,
forcing a rollover and at least one retry. With EE masked, firmware writes DEC
from zero to negative while EXT is held. Enabling EE must deliver EXT then DEC,
both before the same following instruction. A later countdown during a delayed
translated store must wait for its retirement and save the next PC. Handlers
preserve scratch GPRs and XER; the DEC handler reprograms a positive count and uses RFI.
The XER extension checks reserved-bit normalization, carry updates and MCRXR
byte-count preservation. EXT/DEC handlers save XER in SPRG2, deliberately clear
it, and restore it; firmware verifies the exact value across the first event pair.
Firmware checks order, counts, SRR0/SRR1, handler/restored MSR, DAR/DSISR and the
single alias store. Completion requires mailbox retirement and channel drain.

The fixture supplies synchronous ticks on every fourth core cycle while enabled
and pauses them at explicit test phases. It drives ticks before the sampling
edge. These controlled pauses isolate software-write and countdown requests;
this is not a physical bus-clock divider or CDC test. Startup BAT programming
still belongs to the harness. Page refill, runtime BAT programming and combined
cache/60x/MMU integration remain separate work. See `docs/TIMERS.md` and
`docs/COMPILED_FIRMWARE_VERIFICATION.md` for the contract and acceptance record.

## Compiled runtime BAT programming

```sh
make -C toolchain runtime-bat
python3 toolchain/run-rtl-smoke.py --profile runtime-bat --elf toolchain/build/runtime-bat/smoke.elf --build-dir toolchain/build/rtl-runtime-bat
```

This opt-in supervisor/live-context workload starts with empty BAT banks and
programs all mappings through CPU SPR accesses. It reads all sixteen BAT halves,
checks the 603e MFTB read alias, enables translation, writes through a data alias,
invalidates and replaces that mapping, then checks both old and new physical
locations. Pending EXT and DEC remain masked across replacement and are serviced
in priority order after EE is enabled. The fixture supplies delayed abstract
physical memory responses and retirement backpressure. It does not compose
translation with the cache or 60x bus.

GNU as restricts its MFTB mnemonic to time-base selectors, so the BAT alias probe
uses the explicit instruction encoding. `runtime-bat.ld` fixes the mailbox at
`0xfff04000` and keeps the linked program below the alias test data. The harness
requires 25 retired BAT writes, 19 reads, two alias stores, both events, and a
retired success mailbox followed by transport drain. See
[the runtime BAT protocol](../docs/RUNTIME_BAT_PROTOCOL.md) for transaction and
local rejection policies.

## Compiled DSI protection and retry

```sh
make -C toolchain dsi
python3 toolchain/run-rtl-smoke.py --profile dsi --elf toolchain/build/dsi/smoke.elf --build-dir toolchain/build/rtl-dsi
```

The program installs its own BAT mappings, enables instruction/data translation,
and repeats denied LWZU, denied STWU, and repaired LWZU accesses four times.
The handler checks no software condition before recording DAR, DSISR, SRR0,
SRR1 and entry MSR. It either advances SRR0 to skip the fault or changes DBAT1L
permissions and returns to the same instruction to retry. It preserves its GPRs
and CR; its instructions do not alter XER, LR or CTR.

C checks unchanged destination/base registers after skipped accesses, unchanged
physical memory after denied stores, exact fault state, and one successful base
update after each retry. The physical-memory fixture independently requires
12 typed fault retirements and exactly two writes to the protected test word
(initialization and the final permitted store). It supplies delayed responses
and retirement backpressure. This uses abstract physical memory ports; page
miss handlers and physical bus-error recovery remain outside the test.

## Compiled CPU segment-register management

```sh
make -C toolchain segment
python3 toolchain/run-rtl-smoke.py --profile segment --elf toolchain/build/segment/smoke.elf --build-dir toolchain/build/rtl-segment
```

All sixteen registers are written/read through direct and indexed instructions,
including operand aliases and GPR0. The workload checks T=0 normalization, opaque
T=1 retention, and bank preservation across pending EXT/DEC and RFI. It programs
its own BAT identity maps and tests both real and translated execution. The
harness requires 36 SR writes and 38 reads with delayed physical responses and
retirement backpressure. SR contents do not yet drive page translation. See
[compiled segment evidence](../docs/SEGMENT_FIRMWARE.md).

## Compiled prefilled instruction/data page hits

```sh
make -C toolchain page
python3 toolchain/run-rtl-smoke.py --profile page --elf toolchain/build/page/smoke.elf --build-dir toolchain/build/rtl-page
```

The fixture preloads three entries through the public TLB test/control port.
Compiled code owns all BAT/SR setup, switches between two VSIDs for a data page,
and calls a position-independent function through an instruction-page alias.
It checks retained mappings and exact EXT/DEC return context. Delayed physical
responses and retirement stalls are applied by the harness. This profile proves
prefilled page hits, not CPU software refill. See
[page firmware evidence](../docs/PAGE_FIRMWARE.md).

## Compiled CPU TLBIE

```sh
make -C toolchain tlbie
python3 toolchain/run-rtl-smoke.py --profile tlbie --elf toolchain/build/tlbie/smoke.elf --build-dir toolchain/build/rtl-tlbie
```

One ELF runs in three modes, proving CPU TLBIE removes both data ways and the
instruction entry at one set while preserving a neighbor. It also checks GPR0
as an ordinary address operand and retains the page/interrupt workload. TLB
entries are externally preloaded. Each mode ends in an exact expected miss
diagnostic; mailbox 1 only arms that check. See
[TLBIE firmware evidence](../docs/TLBIE_FIRMWARE.md).

## Compiled CPU TLB loads

```sh
make -C toolchain tlbload
python3 toolchain/run-rtl-smoke.py --profile tlbload --elf toolchain/build/tlbload/smoke.elf --build-dir toolchain/build/rtl-tlbload
```

This profile seeds DCMP/ICMP/RPA and SRR1.WAY with CPU instructions, executes
two `tlbld` and two `tlbli` in real mode, then runs the page/interrupt/TLBIE
workload in all three terminal modes. External TLB management stays inactive.
See [CPU-load firmware evidence](../docs/TLB_LOAD_FIRMWARE.md) for acceptance
and the distinction between CPU loading and architectural miss-handler refill.

## CPU-seeded page protection DSI

The `page-dsi` profile builds `page-dsi-smoke.c` and the high-prefix vector in
`page-dsi-handler.S`. CPU `tlbld` installs a protected DTLB entry; the DSI
handler repairs permissions and retries the original update-form load/store.
The fixture keeps the normalized TLB management interface inactive. See
[PAGE_DSI_FIRMWARE.md](../docs/PAGE_DSI_FIRMWARE.md) for checked effects.

```sh
make -C toolchain page-dsi
python3 toolchain/run-rtl-smoke.py --profile page-dsi --elf toolchain/build/page-dsi/smoke.elf --build-dir toolchain/build/rtl-page-dsi
```

## CPU-seeded instruction-page ISI

The `page-isi` profile exercises page PP, segment N and guarded-page fetch
denials in one ELF. Its high-prefix handler repairs the CPU-seeded ITLB entry
or segment descriptor and retries through RFI. See
[PAGE_ISI_FIRMWARE.md](../docs/PAGE_ISI_FIRMWARE.md).

```sh
make -C toolchain page-isi
python3 toolchain/run-rtl-smoke.py --profile page-isi --elf toolchain/build/page-isi/smoke.elf --build-dir toolchain/build/rtl-page-isi
```

The `page-miss` / `rtl-page-miss` targets build and execute a separate variant
of the CPU-installed TLB workload. Three modes retire exact instruction,
load and store miss records after invalidation. The store probe is fixed at
`fff07008`; the original `tlbload` profile is unchanged. These are diagnostic
results, not architectural miss handlers. See
[compiled acceptance](../docs/PAGE_MISS_FIRMWARE.md).

## Software page-table search profiles

`make table-search` builds primary/secondary PTEG search and R/C writeback
firmware. `make rtl-table-search` runs the independent delayed-memory RTL
checker, including changed-bit repair of a way-one resident entry.

`make table-fault` builds the permission and failed-search conversion workload;
`make rtl-table-fault` runs its independent checker. These use the pinned BE
integer profile and the CPU-managed page wrapper with abstract physical memory
ports. They do not establish translated cache/60x integration or OS boot. See
[search contract](../docs/TABLE_SEARCH_HANDLER.md),
[search verification](../docs/TABLE_SEARCH_VERIFICATION.md), and
[fault firmware](../docs/TABLE_FAULT_FIRMWARE.md).

## Translated scalar 60x profiles

`make rtl-table-search-bus` and `make rtl-table-fault-bus` run the same
validated search/fault ELFs through `ppc_core_bat_bus60x`. The independent
RAM responder services only public bus pins, including physical page-table
byte/halfword writes. Both profiles use uncached scalar transactions with
fixed CI/WT/GBL policy; WIMG-driven caching and coherence remain unimplemented.
See [compiled bus evidence](../docs/TRANSLATED_BUS60X_PLAN.md) and
[wrapper contract](../docs/TRANSLATED_BUS60X.md).

## Translated physical I-cache profiles

`make rtl-table-search-cached` and `make rtl-table-fault-cached` execute the
same search/fault ELFs through `ppc_core_bat_cached_bus60x`. Translation and
permission checks precede physical cache lookup. WIMG=0000 instruction reads
use line fills and cache hits; other instruction attributes and all data use
scalar bypass. The target RAM responds only through public 60x pins.
See [cache contract](../docs/TRANSLATED_ICACHE.md) and
[compiled verification](../docs/TRANSLATED_ICACHE_FIRMWARE.md).

The shared fetch transport reserves instruction-queue capacity before a new
request. An already offered request remains stable under backpressure. This
prevents a cache response waiting on a full queue from retaining the unified
translation router while an older instruction needs a data transaction.
