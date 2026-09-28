# Compiled full-decode firmware on the translated cached 60x top

Recorded: `make -C toolchain rtl-full-decode` and `make -C toolchain rtl-all`, commit b3b97d7 plus the firmware, bench and scripted-target changes committed with this record, 2026-09-28.

## What runs

`toolchain/full-decode-smoke.c` and `full-decode-handler.S` build one
big-endian image (profile `full-decode`) for `ppc_core_bat_cached_bus60x`
with the MVP feature set of the translated fit plus `ENABLE_FULL_DECODE`.
`tb/tb_compiled_full_decode_firmware.sv` drives only the 60x pins, reset and
the start handshake, through the scripted target with random ARTRY, DRTRY
and wait states. The image maps itself through IBAT0/DBAT0 (user and
supervisor valid) and runs with IR = DR = 1.

Handlers: DSI (0x300) records DAR, DSISR and SRR0; program (0x700) counts
illegal, privileged and trap causes from SRR1 bits 12, 13 and 14; FP
unavailable (0x800) records SRR0/SRR1 and emulates `fmr` on a soft FPR file,
skipping any other FP instruction; system call (0xc00) returns to
supervisor state. Every handler resumes after the faulting instruction.

| Area | Firmware check |
| --- | --- |
| Illegal | Primary 1, `fsqrt`, the zero word, `lwzu r3,0(r3)` and `tlbia` each count one illegal exception; SRR0 is the last word, SRR1 = 0x00080070. |
| Trap | Fifteen `tw`/`twi` cover each TO bit taken and not taken, `TO=0`, and trap-always: exactly seven traps, SRR1 = 0x00020070. |
| FP unavailable | `fmr f5,f1` copies soft FPR 1 to 5; `lfd` is skipped; SRR0 is the faulting word, SRR1 = 0x70. |
| MSR[FP] | `rfi` with SRR1[FP] = 1 returns with MSR = 0x70; the next FP instruction still faults. |
| PVR, HID0 | PVR = 0x00070200; HID0 reads 0x8000 at reset (the cache reset mode); ICFI set, ICE off, ICE on and all-ones writes keep a loop's result; all-ones reads back 0xbff9fc99. |
| eciwx/ecowx | With EAR[E] = 0, DSI with DSISR 0x00100000 (load) and 0x02100000 (store), DAR = EA, no store; with EAR = 0x80000005 and 0x8000000a both complete. |
| lwarx/stwcx. | An increment loop completes. |
| Privilege | In problem state `mfspr HID0` is privileged and primary 1 illegal (SRR1 PR set); `sc` returns to supervisor. |

The bench checks, from the pins: one atomic read (TT 11010) and write
(TT 10010); two external-control reads (TT 11100) and one write
(TT 10100) with TBST||TSIZ = 0x5, 0x5, 0xa; no other data TT than
write-with-flush and read; instruction fetches are single-beat inhibited
reads or line fills (TT 01110), single-beat ones occur while the cache is
disabled and line fills only while enabled; exactly four HID0 cache
requests (the two writes that change neither ICE nor set ICFI make none);
no external maintenance completion is exposed; no EXT/DEC entry.

The scripted target now treats TT 10010 and 10100 as writes and, for
external-control transfers, reads TBST/TSIZ as the resource ID, not burst
and size.

## Result

`PASS compiled full decode: checks=109080 retires=1288 cycles=25819 atomic=1/1 external=2/1 cache_requests=4 bypass_fetches=8 line_fetches=41 retries=157 drtries=111`

`make -C toolchain rtl-all` passes all 31 compiled-firmware RTL profiles (the 30 existing plus `full-decode`).

## Not established

No real FPU, FPSCR or FP-enabled program exceptions (MSR[FP] never sets).
Exceptions in TGPR mode are covered by
[DIAGNOSTIC_RESIDUALS_FIRMWARE.md](DIAGNOSTIC_RESIDUALS_FIRMWARE.md). The bench checks transfer
classes on the pins, not a device that decodes the resource ID.
