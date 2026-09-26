# Compiled firmware acceptance — 2026-09-21

Recorded: `make -C toolchain rtl-<profile>` per section (e.g. `rtl-smoke`, `rtl-timer`, `rtl-table-fault`), commit pre-repository snapshot, imported in 3e727b6, 2026-09-21 to 2026-09-23 as dated per section.

## CPU TLB-load follow-up, 2026-09-23

All twelve workload profiles pass on the CPU-load revision. TLBIE and CPU-load
profiles each execute three modes. The new profile installs four mappings
through CPU instructions with external normalized TLB requests disabled, then
verifies page execution, VSID switching, EXT/DEC return and invalidation.
Results: 442/5,249, 440/5,224 and 446/5,309 retirements/cycles; deleting the
first load is rejected at cycle 2,214. See [TLB_LOAD_FIRMWARE.md](TLB_LOAD_FIRMWARE.md).
Existing ELFs were reused with rebuilt harnesses, and the new ELF used the pinned
offline compiler. No FPGA timing or automatic miss/refill claim follows.

## CPU TLBIE follow-up

All eleven workload profiles pass against the CPU invalidation revision. Ten
prior ELFs are reused with rebuilt harnesses. The new ELF runs three modes
checking both data ways and an instruction entry are invalidated, with a
neighboring entry retained. The modes pass 382/4,609, 380/4,576 and 386/4,665
retirements/cycles. A wrong-set negative fails mailbox `88000004`.
[TLBIE_FIRMWARE.md](TLBIE_FIRMWARE.md) explains why the terminal misses are
expected diagnostics rather than architectural refill. No new FPGA timing
evidence is claimed.

## Prefilled page-hit follow-up

All ten workloads pass against the page-capable router. Nine prior ELF programs
are reused with rebuilt RTL harnesses; the page ELF is newly compiled with the
pinned offline toolchain. Page acceptance passes four I-page retirements, six
SR writes, four BAT writes, one EXT, one DEC and 356 retirements / 4,273 cycles.
The instruction-page expected-result negative fails mailbox `87000002`.
[PAGE_FIRMWARE.md](PAGE_FIRMWARE.md) records reproduction and the external-preload
limitation. No page miss/refill or timing claim follows.

## Segment-register follow-up, 2026-09-22

All nine workloads pass against the CPU segment-register revision. The eight
prior ELF programs are reused with rebuilt RTL harnesses; the ninth is newly
compiled with the pinned offline toolchain. Segment acceptance passes 36 SR
writes, 38 reads, four BAT writes, one EXT, one DEC and 830 retirements / 9,271
cycles. Its readback negative control fails the exact intended mailbox check.
See [SEGMENT_FIRMWARE.md](SEGMENT_FIRMWARE.md) for reproduction and limitations.

## Timer follow-up

The new timer-enabled BAT workload passes **372 retirements, 3,937 cycles,
one external interrupt, two decrementer interrupts, eight IR/DR transitions,
one alias store, 32 reads and 43 writes**. It requires a successful
TBU/TBL/TBU retry across rollover, then EXT before pending DEC at the same EE
enable boundary, and a countdown DEC after a delayed translated store. Exact
resume labels, MSR/SRR1, preserved DAR/DSISR and single-store behavior are checked
by compiled C. Both handlers preserve scratch GPRs. Success includes final
mailbox retirement and physical channel drain. Controlled tick pauses are a
fixture, not physical clock-generation evidence; see [`toolchain/README.md`](../toolchain/README.md).

All five prior profiles also pass against this revision with unchanged results:
baseline 30/187, alignment 1,516/8,421, synthetic fetch 186/1,123, live context
101/1,123 and external IRQ 198/2,187 (retirements/cycles).

The negative check asserts that image bytes at `0x1164` are `28090040`, then
changes byte `0x1167` to `41`, corrupting the expected DEC-handler MSR. Running the timer binary with that
image and `+TOHOST=fff02000` fails through `firmware failure mailbox cycle=2560`
(SIGABRT), not timeout. Check the original bytes before applying the offset to
a rebuilt image.

## External-interrupt follow-up

All five firmware profiles pass against the external-interrupt/alignment-path
revision. The previous four retain their counts below. The new BAT-backed
external-interrupt workload passes **198 retirements, 2,187 cycles, two interrupt
acceptances, six IR/DR transitions, one alias store, 19 reads and 22 writes**.
The first IRQ is held while masked and enters immediately after EE enable;
the second waits for a delayed translated store. C checks both linked resume
labels, handler MSR, saved SRR1, DAR/DSISR preservation and restored translation.
Success requires mailbox retirement and channel drain. This profile does not
combine BAT translation with the cached physical measurement top.

Prior ELFs are unchanged.

The negative check asserts that image bytes at `0x1e0` are `28050040`, then
changes byte `0x1e3` from `40` to `41`, corrupting the first expected handler
MSR. The existing IRQ simulator, run with that memory image and
`+TOHOST=fff01000`, fails via `firmware failure mailbox cycle=1240` (SIGABRT),
not timeout. Verify the original instruction bytes
before reusing this offset with a rebuilt ELF. See [`toolchain/README.md`](../toolchain/README.md) for
positive reproduction and [`EXTERNAL_INTERRUPT_VERIFICATION.md`](EXTERNAL_INTERRUPT_VERIFICATION.md) for independent
directed and full-regression evidence.

## Live-context follow-up

The subsequent live-context/ring-arithmetic revision passed all four firmware
profiles. Baseline, alignment and synthetic fetch retain the counts recorded
below. The new live BAT workload passed **101 retirements, 1,123 cycles, four
IR/DR context transitions, one mapped alias store, seven reads and eleven
writes**. Context followed real mode → translation → real-mode SC handler →
translated RFI return → real mode. Final mailbox retirement and physical channel
drain were required. See [`LIVE_BAT_CONTEXT.md`](LIVE_BAT_CONTEXT.md) for the integration boundary.

The negative check changed the expected handler MSR from `0x40` to `0x41`:
assert image bytes at offset `0x1d8` equal `280a0040`, then change byte `0x1db`
to `41`. Running the existing live binary with this modified memory image and
`+TOHOST=fff01000` failed via `firmware failure mailbox cycle=946` (SIGABRT),
not a watchdog. As with the earlier mutation, the byte
assertion must precede use on any newly compiled image.

## Earlier typed-fetch snapshot

All three profiles passed after the typed fetch-fault and rename/FIFO timing
changes. Verilator was 5.020 (Debian 5.020-1). Firmware used the repository's
pinned cross-toolchain profile; see [`toolchain/README.md`](../toolchain/README.md) for build commands.

| Profile | Environment | Accepted retirements | Cycles | Result |
| --- | --- | ---: | ---: | --- |
| Baseline | Cached physical 60x wrapper | 30 | 187 | Success mailbox; 5 refills, 3 reads, 3 writes |
| Alignment | Cached physical 60x wrapper | 1,516 | 8,421 | 24 handler round trips; 24 refills, 226 reads, 139 writes |
| Fetch faults | Abstract core with synthetic typed responses | 186 | 1,123 | Exactly 2 injected/retired ISI events; 20 reads, 26 writes |

Success requires accepted retirement of the final mailbox store, not just a
memory write. The cached profiles also drain their physical transport. The
fetch profile verifies protection/guarded saved state, DAR/DSISR preservation,
RFI retry and subsequent successful calls. It does not test a real translation
producer, physical TEA recovery or interrupt handling.

ELFs and build products are generated artifacts.

## Negative fetch-firmware check

The test changed the compiled protection-SRR1 expectation from high half
`0x0800` to `0x0801`. The original image bytes at offset `0x1dc` were
`6d490800` (`xoris r9,r10,0x0800`); changing byte `0x1df` to `01` produced
`6d490801`. The simulation failed through the firmware failure mailbox at
cycle 725, rather than timing out.

To reproduce against that ELF, first run the positive fetch profile to
generate `toolchain/build/rtl-fetch-fault/memory.hex`. From the repository root:

```sh
python3 - <<'PY'
from pathlib import Path
image = Path('toolchain/build/rtl-fetch-fault/memory.hex')
data = bytearray(int(line, 16) for line in image.read_text().split())
assert data[0x1dc:0x1e0] == bytes.fromhex('6d490800')
data[0x1df] = 1
Path('build/ppc-fetch-corrupt-expectation.hex').write_text(
    ''.join(f'{byte:02x}\n' for byte in data))
PY
ulimit -c 0
toolchain/build/rtl-fetch-fault/obj/Vtb_compiled_fetch_firmware \
  +IMAGE=build/ppc-fetch-corrupt-expectation.hex +TOHOST=fff01000
```

The last command is expected to fail with `firmware reported failure`. The
assertion prevents applying this offset blindly to a differently compiled ELF.


## Bounded rename-owner retention follow-up — 2026-09-21

All six existing ELF workloads were rebuilt against the changed RTL and passed.
The ELF artifacts were reused; no compiler or firmware source change was needed.
Negative firmware controls were not repeated in this round.

| Workload | Retirements | Cycles |
| --- | ---: | ---: |
| baseline | 30 | 187 |
| alignment | 1516 | 8421 |
| fetch | 186 | 1123 |
| live | 101 | 1123 |
| irq | 198 | 2187 |
| timer | 372 | 3937 |

The existing profile commands above reproduce these checks.
[Recovery verification](RECOVERY_METADATA_VERIFICATION.md) records the focused
RTL gates. No new full regression or FPGA fit accompanies this round.


## XER state-saving follow-up — 2026-09-21

The timer firmware now checks explicit XER reserved-bit normalization, ADDIC
carry updates preserving byte count, and MCRXR flag clearing preserving byte
count. It seeds `0xa0000055` before enabling EE; EXT and DEC handlers save XER
in SPRG2, deliberately clear it and restore it. Firmware observes the original
value at both handler entries and immediately after the first event pair.
The final program passes in **436 retirements / 4,494 cycles**, with one EXT,
two DEC events, eight context transitions, one alias store, 33 reads and 46 writes.
This replaces the earlier timer workload's retirement/cycle totals, not its
historical evidence.

All six workloads were rebuilt and passed on the frozen final RTL. The five
unchanged workloads retain their previous retirement/cycle totals.

A negative control changes the first XER comparison at `0xfff01028` from
`cmpwi r9,127` (`2c09007f`) to `cmpwi r9,126`. The corrupted image fails
through the firmware mailbox at cycle 1,226 (SIGABRT), rather than timing out. No other workload negative
controls were repeated in this round.

Build: existing pinned offline container, `make timer`, with `SOURCE_DATE_EPOCH=0`.
Run: existing `run-rtl-smoke.py --profile timer` command.

[XER contract](XER_ACCESS.md) and [focused verification](XER_VERIFICATION.md)
record the architectural boundary and independent tests. No full regression or
FPGA fit was run for this slice; previous fit archives remain historical.

## Software table-search sequence — 2026-09-23

All twenty compiled workloads pass against the final sources. The eighteen
existing workloads retain their expected results, including both resident-way
miss-entry modes. Two new profiles cover actual software primary/secondary
PTEG search, physical R/C writeback, full effective miss addresses, all data
PP/key combinations and ordinary absent/protected/guarded ISI/DSI conversion.

| Profile | Retirements | Cycles | Independent checks |
| --- | ---: | ---: | ---: |
| table-search | 5,152 | 55,018 | 300,164 |
| table-fault | 73,464 | 782,367 | 3,485,002 |

The latter observes 21 miss cases, 10 ordinary faults and 11 allowed fills.
Omitted PTE R/C writeback fails at cycle 30,694; a wrong guarded ISI syndrome
fails at cycle 115,083. Sources stayed unchanged through the final compiled
suite and negative controls. Full regression also passes
199 registered simulation configurations and 243 Python checks, plus 43
standalone lint profiles and both existing measurement wrappers.

Reproduce with the pinned compiler and `make table-search table-fault`, then
`run-rtl-smoke.py --profile table-search` or `--profile table-fault` with the
corresponding ELF/build paths. The Makefile's `rtl-table-search` and
`rtl-table-fault` targets supply those paths. See
[TABLE_SEARCH_VERIFICATION.md](TABLE_SEARCH_VERIFICATION.md) and
[TABLE_FAULT_VERIFICATION.md](TABLE_FAULT_VERIFICATION.md). This remains the
abstract physical-port page wrapper; translated cache/60x and new FPGA timing
acceptance are still open.

## Translated scalar 60x acceptance — 2026-09-23

The twenty existing compiled workloads still pass. Two additional execution
profiles run the same table-search and table-fault ELFs on the translated
scalar 60x wrapper. Architectural retirements and final memory/fault results
agree with the abstract-port profiles. Search passes 623,059 checks at
124,927 cycles; fault passes 9,604,532 checks at 1,772,615 cycles.
Removing PTE R/C writeback is rejected at cycle 69,737; an incorrect guarded
ISI cause is rejected at cycle 261,790. No ELF or established RTL change was
needed. See [bus evidence](TRANSLATED_BUS60X_FIRMWARE.md).

The full regression passes 202 registered simulation configurations, 243
Python tests and 45 standalone lint profiles. Sources stayed frozen. This
validates uncached scalar translation over physical
bus pins; translated I-cache, complete attribute handling and FPGA timing
remain separate acceptance gates.
