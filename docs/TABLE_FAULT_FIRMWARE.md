# Compiled 603e table-search fault firmware

**Status:** The pinned compiler build and combined RTL workload pass: 21
miss cases, 10 ordinary faults and 11 successful fills. This image builds on the
accepted CPU-driven PTEG search and R/C update image. Its table data is
initialized by CPU stores into physical RAM, not supplied by the testbench.

`toolchain/table-fault-smoke.c`, `table-fault-vector.S`, and `table-fault.ld`
use the shared `table-search-handler.S`. The dedicated linker places ordinary
DSI and ISI vectors at `0xfff00300` and `0xfff00400`, the three TLB miss
vectors at `0xfff01000`, `0xfff01100`, and `0xfff01200`, main at
`0xfff02000`, the mailbox at `0xfff04000`, and a fixed case marker at
`0xfff0b000`. The stack grows down from `0xfff10000`; SDR1 points to the
64-KiB page table starting there. The fixture backs physical RAM through
`0xfff2ffff`, but does not preload a PTE or translation.

The C image runs 21 sequential cases. `begin_case` writes the marker, clears
`miss_count` and `miss_records[4][8]`, and executes `sync; tlbie; sync; isync`
for the target set. The shared miss handler may therefore keep its four-record
bound. Ordinary faults accumulate separately in `fault_count` and
`fault_records[16][6]`, in the exact order `{marker, SRR0, SRR1, DAR, DSISR,
entry_MSR}`. Ten cases must reach an ordinary vector. The vector saves normal
GPR0–GPR3 in SPRG0–SPRG3 and CR in memory before using the registers, records
the synthesized state, skips a denied data instruction by changing SRR0 to
`PC+4`, or returns from a still-unmapped instruction page to the caller's LR.
It restores CR and normal GPRs before `rfi`. A byte-load probe uses nonzero
EA `0x1000c003`; the other miss EAs also have nonzero offsets so DMISS/IMISS
must retain the **full** accepted EA.

| Marker | Access and EA | PTE placement | Expected ordinary fault |
| --- | --- | --- | --- |
| 1 | I miss, `0x20001004` | no PTE in HASH1 `fff19e40` or HASH2 `fff16180` | ISI, SRR1 `40000070` |
| 2 | byte D load, `0x1000c003` | no PTE in `fff18e00` or `fff171c0` | DSI, DAR full EA, DSISR `40000000` |
| 3 | D store, `0x1000d008` | no PTE in `fff18e40` or `fff17180` | DSI, DAR full EA, DSISR `42000000` |
| 4 | I fetch, `0x20002008` | HASH1 `fff19e80` slot 4: `802b3c00 / fff0d00a` (`G=1`) | ISI, SRR1 `10000070` |
| 5 | I fetch, `0x2000300c`, SR2.Ks=1 | HASH1 `fff19ec0` slot 2: `802b3c00 / fff0e000` (`PP=00`) | ISI, SRR1 `08000070` |

Markers `16 + 8*KEY + 2*PP + WRITE` cover all sixteen data combinations
with KEY 0/1, PP 0–3 and load/store at EA `0x1000b004`. The target is HASH1
`0xfff18fc0` slot 5, PTE0 `0x80091a00`, and PTE1 initially
`0xfff0c000 | PP`, with R=C=0. A denial occurs for `(KEY && PP==0)` or for
a store with `(PP==3 || (KEY && PP==1))`. Five combinations are denied. Their
DSISR is `0x08000000` plus `0x02000000` for stores; DAR is the full EA, and
PTE1 and physical data remain unchanged. An allowed load sets only R
(`PTE1 | 0x100`); an allowed store sets R and C (`PTE1 | 0x180`). The image
checks all twelve relevant PTEGs after each case so unrelated words cannot
silently change. A denied case may not load a TLB entry or issue the attempted
physical access.

The 603e User's Manual §5.5.2.2 and Figures 5-18/19 require a failed PTE
search to synthesize ISI/DSI and clear TGPR before entering the ordinary
handler. The PowerPC Programming Environments Manual Table 6-10 assigns ISI
SRR1 bit 3 (`0x10000000`) to guarded fetch and bit 4 (`0x08000000`) to page
permission denial. The 603e manual's worked `doISIp` example uses bit 4 for
its guarded branch; this image follows the architectural table so the three
ISI causes remain distinguishable. For BE data misses, the manual's worked
handler copies full DMISS to DAR. LE address adjustment, instruction direct
store, and nested miss handling are outside this bounded image.

The integration gate exposed and corrected an ordinary DSI return bug:
`addi r0,r0,4` uses literal zero as its base on PowerPC. The final vector
reads SRR0 into r1 and uses `addi r1,r1,4` before writing it back; r1 is
restored from SPRG1 before RFI. The ELF also gives its case marker a separate
load segment so it cannot overlap the fixed instruction-probe segment.
