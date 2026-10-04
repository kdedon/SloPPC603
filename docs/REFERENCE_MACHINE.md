# Whole programs against DingusPPC

`make -C sim test-reference-machine` runs the demo SoC firmware (hello,
Dhrystone, CoreMark, soft-float Whetstone and the opcode self-test) on the
demo SoC top, with both caches on and BAT data and instruction translation on,
in lockstep with the DingusPPC CPU, MMU and exception code.
`make -C sim test-reference-machine-mmu` does the same for the MMU stress image
on the `ppc603e` package top, through software TLB reloads, page faults,
direct-store segments and random external and decrementer interrupts. Both
need the `../dingusppc` checkout (`REFERENCE_DIR`) and prebuilt images
(`DEMO_FW_DIR`, `MACHINE_MMU_ELF`; see [toolchain/README.md](../toolchain/README.md)).

DingusPPC is a comparison reference, not a source of truth. Agreement shows
consistency; every mismatch is decided against the manuals.

## Method

The bench writes one line per retirement edge (`tb/machine_trace.svh`, enabled
by `+RETIRE_TRACE=<file>`): PC, instruction, how many instructions retired
(2 when CQ[1] retires beside the head), whether it faulted, every architectural
register that changed, and the physical stores the core issued since the
previous line. The registers are r0–r31, CR, XER, LR, CTR, MSR, SRR0, SRR1, DAR,
DSISR, SPRG0–3 and the four TGPRs. The RTL writes into a FIFO that
`sim/cosim/machine_runner.cpp` reads, so no trace is stored.

For each line the runner steps the reference once per retired instruction and
then requires:

- the same PC before the step;
- every listed register equal afterwards, the whole set, not only the ones
  that changed;
- each stored byte present at that address in the reference's memory, or, for
  the I/O window, the same byte written to the reference's I/O device in the
  same order, and no reference I/O write the RTL did not make;
- a faulted RTL retirement to be an exception in the reference.

It ends at the exit store (the SoC `EXIT` register, or the firmware mailbox)
and reports what it compared. Five mutations of the first 200,000 records of
the first program (a GPR, MSR and CR bit, a store byte, a dropped record) must
each fail.

## What the runner supplies

These are implementation timing or state the reference cannot have. Each is
taken from the RTL record and counted in the summary.

| Item | Why | Handling |
|---|---|---|
| Loads from the SoC registers (`io_reads`) | Cycle, retired and performance counters are timing | The reference device returns the value the RTL load retired with |
| `mftb`, `mfspr` of TBL/TBU/DEC (`timing_reads`) | Timer values | The destination takes the RTL value |
| `mfspr` IMISS/ICMP/DMISS/DCMP/HASH1/HASH2/RPA | Miss state the reference never forms | The destination takes the RTL value |
| External and decrementer interrupts (`interrupts`) | Asynchronous; taken between retirements | When the RTL's next PC is `0x500`/`0x900`, the reference enters that exception there, SRR0 = the next instruction |
| ITLB/DTLB miss entry (`tlb_misses`) | The reference translates by hardware table search and has no TGPRs | On a faulted RTL retirement that set MSR[TGPR], the reference does not execute the instruction; it takes SRR0, SRR1, MSR and CR from the RTL, maps r0–r3 to the TGPRs and jumps to the RTL's vector. The handler then runs in both. `tlbld`/`tlbli` are no-ops in the reference, so the retried access uses its own table search over the same page table |

## Adapter corrections

Shared with the firmware lane (`sim/cosim/reference_adapter.h`); those listed in
[REFERENCE_FIRMWARE.md](REFERENCE_FIRMWARE.md#adapter-corrections) also apply.
In every case the RTL follows the manual. None required an RTL change.

| First seen | Reference behavior | Manual | Correction |
|---|---|---|---|
| chip-mmu-stress | `rfi` keeps MSR[TGPR] and copies reserved SRR1 bit 0 | PEM `rfi`: MSR[16–23,25–27,30–31] from SRR1; 603e UM: `rfi` clears TGPR | Rebuild MSR from that mask after `rfi` |
| chip-mmu-stress | Aborts on direct-store segments | 603e UM: no direct-store; a T=1 data access takes DSI with DSISR[5], DAR = EA; a fetch takes ISI with SRR1[3]; cache operations are no-ops (PEM 5.1.5) | Check the RTL's entry against those fields, then take it; skip the cache operation |
| selftest | `tlbld`/`tlbli` run in problem state | Supervisor-level: privileged program exception | Raise it |
| selftest | Misaligned `stwcx.` executes | UM 4.5.6: alignment | Raise alignment; DSISR[15–21] from the XO (Table 4-13), which the reference leaves clear |
| selftest | A misaligned halfword or word access crossing a 4-Kbyte page is split | UM 4.5.6.1: alignment under data translation | Raise alignment |
| selftest | `dcbz` to caching-inhibited or write-through memory zeroes it | UM 4.5.6: alignment | Raise alignment for BAT-mapped W or I blocks; DSISR from Table 4-13 |

## Tolerances

Only fields the manuals leave undefined or implementation-dependent, each
counted in the summary:

| Field | Source | Handling |
|---|---|---|
| `divw`/`divwu` rD and CR0[LT,GT,EQ] for a zero divisor or `0x80000000 / -1` (`undefined_fields`) | PEM `divw`, `divwu` | Take the RTL's values; XER[OV,SO] still compared |
| Alignment DSISR[27–31] for forms other than update, `lmw` and string (`undefined_fields`) | PEM Table 6-12 | Take the RTL's bits |
| PVR revision (`undefined_fields`) | UM 2.1.1 | Version (upper half) compared; revision taken |
| Loads from a block after `dcbi` (`dcbi_loads`) | PEM `dcbi`: a modified block is discarded, so memory depends on the cache | The RTL's loaded value is taken and written into the reference's memory |
| Failed `stwcx.` (`failed_stwcx`) | The core offers the write before the reservation decides it; CR0[EQ] clear means nothing was written | Its store offer is not compared |
| A store's write after younger records (`late_stores`) | UM 1.1.4.3: the store queue performs a completed store later | A record with writes needs a retired store not yet matched by an earlier record with writes; its bytes are compared against the reference's memory then, and the reference's I/O writes wait for it |
| Branches removed at dispatch (`removed_branches`) | UM 6.3.1: a branch with no SPR write back retires in the BPU | `rb=<n0>,<n1>` on the next record; the reference steps that many branches (each checked to be a branch without LK or CTR decrement) before the head and before CQ[1] |

## Not established

- Final RAM is not compared: dirty data-cache lines never reach the bus model.
  Stores are compared as the core issues them and loads through their results.
  `dcbz` on cacheable memory is a cache operation and shows only through later
  loads.
- The reference has no caches or TLBs, so cache and TLB state (replacement,
  stale entries, R/C bits written by the reference's table search) is compared
  only where it changes architectural results.
- No timing: the reference is not a cycle oracle.
- FPU images: the runner clears MSR[FP] as the non-FPU SoC does, so only the
  soft-float programs are compared.

## Results

See the `Recorded:` lines in [REFERENCE_RUNNER.md](REFERENCE_RUNNER.md#whole-machine-lockstep).
