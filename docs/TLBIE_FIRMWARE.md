# Compiled CPU TLB invalidation acceptance

The `tlbie` profile uses one compiled ELF in three fixture-selected modes. Four
TLB entries are preloaded through the public normalized control interface:
DTLB set 8 ways A/B under VSIDs `1234`/`2345`, ITLB set 8 under VSID `5678`,
and a neighboring ITLB set 0 entry. CPU code owns all BAT and SR programming.
The program exercises the mappings and EXT/DEC return before invalidating them.

The first `tlbie` uses ordinary GPR0 containing `deadf000` (set 31), proving
that treating r0 as literal zero would incorrectly remove the still-needed
set 0 mapping. The second uses `deac8234`: its segment/tag/offset differ from
the mapped addresses, while `EA[16:12]` still selects set 8. Explicit SYNC/ISYNC
sequences surround invalidation. The code runs through a stable BAT mapping.
After the second invalidation, a call through neighboring ITLB set 0 must still
return the expected value.

The modes then demand one exact terminal diagnostic:

| Mode | Access after invalidation | Required outcome | Retirements / cycles |
| --- | --- | --- | ---: |
| 0 | DTLB way A mapping at `10008000` | Ordered load diagnostic at linked probe `fff07000`, no GPR write | 382 / 4,609 |
| 1 | ITLB mapping at `20008000` | Instruction-page miss halt with no physical request | 380 / 4,576 |
| 2 | DTLB way B after CPU switches SR1 | Same ordered load diagnostic, proving the other way was invalidated | 386 / 4,665 |

Every mode requires exactly two retired TLBIE instructions, eight successful
instruction-page retirements before the terminal access, both earlier physical
data writes, one EXT and one DEC, and no physical access for the final miss.
Delayed memory and retirement backpressure remain enabled. The mailbox value 1
only arms the expected terminal check; it is not success by itself. A missing
invalidation allows execution to reach failure mailbox `88000004`. These expected
misses are diagnostic outcomes, not resumable architectural miss exceptions.

Build with the pinned offline compiler from the toolchain README, then run:

```sh
make -C toolchain tlbie
python3 toolchain/run-rtl-smoke.py --profile tlbie --elf toolchain/build/tlbie/smoke.elf --build-dir toolchain/build/rtl-tlbie
```

The runner executes all three modes. The negative control asserts image bytes
at offset `130c` are `3d20deac`, changes the final byte to `ad`, and runs mode 0.
That flips the selected set from 8 to 24; the expected miss does not occur and
the test rejects failure mailbox `88000004` at cycle 4,849. Recheck original
bytes before reusing the offset with another build.

This slice adds CPU invalidation. TLB loading still uses fixture preloads;
TLB load instructions, miss SPRs, TGPR, software table search/refill/retry,
page fault exceptions, cache/bus composition and FPGA timing remain separate work.
