# Compiled runtime BAT acceptance

Initial acceptance on 2026-09-22: the pinned offline compiler build and
`run-rtl-smoke.py --profile runtime-bat` pass. Final protocol verification is
recorded separately in [RUNTIME_BAT_VERIFICATION.md](RUNTIME_BAT_VERIFICATION.md).

The program starts without harness-installed mappings, clears all sixteen BAT
halves, installs instruction/data identity maps and a data alias, reads every
half plus the MFTB alias, enables IR/DR, replaces the alias mapping through
inactive intermediate state, and confirms old/new physical data. Pending EXT
and DEC cross replacement while masked; both handler state and priority are
checked after enabling EE. Physical responders introduce delay and retirement
is periodically held. Cache/60x integration and arbitrary C/ABI support are
outside this acceptance.

Result: **25 BAT writes, 19 reads, one EXT, one DEC, two alias stores, 401
retirements, 23 physical reads, 37 writes, 4,834 cycles.**

The six prior ELF workloads also passed against the changed RTL: basic cached
BE (30 retirements), alignment (1,516), fetch faults (186), live context (101),
external interrupts (198), and timer/XER (436). Those ELF files were reused;
the runtime-BAT ELF was newly compiled. No FPGA fit was run for this wave.

## Negative control

The generated memory image was copied outside the repository. At offset
`0x10e0`, the original instruction bytes `2c 0a 00 00` were asserted before
changing the final byte to `01`: the IBAT1U readback now incorrectly expects
one instead of its reset/cleared zero. No DUT source or original ELF changed.
The otherwise identical simulator fails by SIGABRT at cycle 2,100 with
`firmware failure mailbox=81000212`, the expected selector-530 failure code.
This is a diagnostic failure, not a watchdog timeout.

Logs: `/tmp/ppc-runtime-firmware.log`, `/tmp/ppc-runtime-old-firmware.log`,
`/tmp/ppc-runtime-bat-negative.log`. Temporary logs are local convenience
artifacts; reproduce using the commands in `toolchain/README.md`.

## Initial passing source boundary

| Input | SHA256 |
| --- | --- |
| `rtl/ppc_core.sv` | `452ef4f0d91ab5ff2c0e360c46565f416d7a79b467e75ba91d4f349ca9c2e827` |
| `rtl/ppc_special.sv` | `31ca8094ceeb7feeb64d646c33ad0ab55469d2b569ff7408ab5775d85224c850` |
| `rtl/ppc_decode.sv` | `6e66d2e448793b6731d33421cad8ac9dd6119267c96267c39fb06bbbd56e86fc` |
| `rtl/ppc_bat_service.sv` | `8ca313a7b383df73337ccbc1c11f6653926f8da78b138cffe13c3c2cec402749` |
| `rtl/ppc_bat_memory_router.sv` | `67f9eb7fd921ea0bab32cc037b5863f338aa3cff9dc5d7c670c4ce526454f691` |
| `rtl/ppc_core_bat.sv` | `2a58195d793d215c30e8aee7fda3c93b3ff1907391ef8aeaceb27414203a5061` |
| `tb/tb_compiled_runtime_bat_firmware.sv` | `b103a566ffec85847304cdcb334126f12e0b1b17a4bba39ad8cfa704821375f8` |
| `toolchain/runtime-bat-smoke.c` | `9d191bc31b1017ab66f1e57dd5904d0aaa0f2f46a02e8d20fec8077f93b2ad8f` |
| `toolchain/runtime-bat.ld` | `2417769d7639a1cbffdedd22de7836055c73e0c2f7bba377ea0c769bd242cfe9` |
| `toolchain/build/runtime-bat/smoke.elf` | `549c8aa7b14cbdbce8379f464b960101e0e9dcfbf38fada1a7e3aab906ffefe7` |

## Early-mutation assertion control

A temporary copy of the service added a committed-bank assignment inside the
prepare branch. The runtime service fixture with assertions enabled failed at
simulation time 45 in the bank-stability assertion, before the transaction could
be accepted as correct. The real service source was unchanged. This demonstrates
that the assertion detects premature mutation; it is not a separate public-port
readback oracle. Artifacts: `/tmp/ppc-runtime-early-write/`.
