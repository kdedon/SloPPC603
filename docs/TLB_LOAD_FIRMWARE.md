# Compiled CPU TLB-load acceptance

The `tlbload` profile extends the TLBIE workload with CPU-installed page
translations. At startup, IR=DR=0 and the external normalized TLB management
request remains inactive for the entire simulation. CPU instructions write
DCMP/ICMP, RPA and SRR1.WAY, then execute two `tlbld` and two `tlbli` operations:

| Bank | EA | VSID | Way | Physical page |
| --- | --- | --- | --- | --- |
| Data | `10008000` | `001234` | 0 | `fff08000` |
| Data | `10008000` | `002345` | 1 | `fff09000` |
| Instruction | `20000000` | `005678` | 0 | `fff06000` |
| Instruction | `20008000` | `005678` | 0 | `fff06000` |

RPA supplies C=1, PP=2 and WIMG=0; its R bit is set to demonstrate that the TLB
load ignores it. Explicit SYNC/ISYNC surround loads. Software then programs
BATs and SRs, enables translation, verifies VSID-specific data stores and
instruction-page calls, and handles one external and one decrementer interrupt.
It finally performs two CPU TLBIE instructions and checks the same three
terminal miss cases as [TLBIE_FIRMWARE.md](TLBIE_FIRMWARE.md). A neighboring
instruction mapping must survive. Delayed memory and retirement backpressure
remain enabled. Mailbox 1 only arms the terminal checks; it does not itself
prove successful acceptance.

The harness requires two retired loads of each bank, eight compare/RPA writes,
all prior I/D page effects, correct interrupt return state, both indexed data
ways invalidated, and no physical access for the final miss. The management
interface cannot install a fallback entry. These final misses remain ordered
diagnostics: CPU load instructions are not automatic miss handling or a
software page-table walk.

Build and run using the pinned toolchain described in `toolchain/README.md`:

```sh
make -C toolchain tlbload
python3 toolchain/run-rtl-smoke.py --profile tlbload --elf toolchain/build/tlbload/smoke.elf --build-dir toolchain/build/rtl-tlbload
```

The runner executes all three terminal modes. The profile keeps the existing
firmware layout, including main at `fff01000`; that address must move before a
high-prefix architectural I-TLB miss handler can occupy its vector.

## Acceptance, 2026-09-23

All three modes pass against the integrated CPU/router/service RTL:

| Mode | Retirements | Cycles | Final access |
| --- | ---: | ---: | --- |
| 0 | 442 | 5,249 | Invalidated data way A |
| 1 | 440 | 5,224 | Invalidated instruction mapping |
| 2 | 446 | 5,309 | Invalidated data way B after SR switch |

Each mode performs 27 reads, 45 writes, eight instruction-page retirements,
twelve instruction-page physical fetches, and one EXT/DEC pair. The other
eleven compiled profiles also pass against the same production sources.

A negative control checks image bytes at offset `1050` equal `7c00ffa4`
(`tlbld r31`), then replaces that instruction with `4c00012c` (`isync`).
Mode 0 rejects the premature page miss at cycle 2,214, proving that fixture
preloading cannot hide the missing CPU-installed mapping. Assert the original
bytes before reusing this offset with another build.

Local logs: `/tmp/ppc-tlbload-all-firmware.log`, per-profile
`/tmp/ppc-tlbload-fw-*.log`, and `/tmp/ppc-tlbload-negative.log`. Temporary
logs are not durable CI storage. No FPGA fit or architectural miss/refill/retry
acceptance follows from these tests.
