# Full decode verification

Recorded: `make -C sim -j2 ci` and `./quartus/translated/build.sh --docker`, commit `3f70e43`;
`python3 sim/tools/isa_check_rtl.py`, `make -C toolchain rtl-full-decode rtl-full-decode-negative`,
commit `bc3fbd9`; 2026-09-28. All pass.

Contract: [FULL_DECODE.md](FULL_DECODE.md).

## Results

| Check | Target | Result |
| --- | --- | --- |
| Decode sweep | `make -C sim test-decode-sweep` | 85,376 probes, none diagnostic: 71,254 illegal, 12,647 FP unavailable, 15 trap, 33 new forms, 1,440 privileged undefined SPRs, 1,427 unchanged from the profile without full decode |
| Core bench | `make -C sim test-core-full-decode` | checks=8281, events=70, retires=730, transfers=6, cache requests=2 |
| Exception state | `make -C sim test-exception-state` | 227 checks without full decode; 12 with it: MSR[FP] stays 0 through state load, `rfi` and FP-unavailable entry |
| ISA metadata against RTL | `python3 sim/tools/isa_check_rtl.py` (also in `check-spec`) | 17 profiles × 78,112 probes, 0 mismatches; `full_decode` accepts 13,117, `all` 13,522 |
| Compiled firmware | `make -C toolchain rtl-full-decode` | checks=109,080, retires=1,288, cycles=25,819, atomic TT 1/1, external-control TT 2/1, HID0 cache requests=4, 8 inhibited and 41 line fetches, 157 ARTRY, 111 DRTRY |
| Negative control | `make -C toolchain rtl-full-decode-negative` | Same image without full decode stops at its first undefined opcode (`04000000` at `fff01070`), as required |
| Full gate | `make -C sim -j2 ci` | 462 regression PASS lines, 231 + 28 + 15 Python tests, container firmware build, 31 compiled-firmware profiles |
| Coverage | `make -C sim coverage` (in `ci`) | 76.5% of `rtl/` lines (1,409 of 1,841), 19 runs including `full-decode`, 14 waived arms, none uncovered |
| Lint | `make -C sim lint` (in `ci`) | Includes `ppc_core` with SUP, LIVE, FULL_DECODE, RESERVATION and CACHE |
| Fit | `./quartus/translated/build.sh --docker` | Meets 50 MHz; see [TRANSLATED_SYNTHESIS_BASELINE.md](TRANSLATED_SYNTHESIS_BASELINE.md) |

## What this establishes

Every 32-bit word decodes to an executed form or the exception the manuals
give it, on the decoder and on the core. Profiles without full decode decode
as before and still store MSR[FP]. The compiled firmware's own handlers check
the 0x700 causes, 0x800 entry, PVR/HID0/HID1/EAR and eciwx/ecowx; the bench
checks the 60x transfer classes and HID0 instruction-cache requests.

## What it does not

No FPU: FP instructions are verified only to take FP unavailable. Transfer
classes are checked against the bus model, not a 603e trace.
