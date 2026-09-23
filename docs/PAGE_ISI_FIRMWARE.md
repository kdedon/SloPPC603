# Compiled instruction-page ISI acceptance

The `page-isi` profile uses one big-endian PowerPC ELF and the opt-in `ENABLE_PAGE_INSTRUCTION_EXCEPTIONS` router path. The CPU configures its own bootstrap BAT, segment register and instruction TLB; the external normalized TLB management interface never offers a request. Code at physical `fff01000` remains BAT-backed while IR=1. The test function at effective `20000000` is physically stored at `fff06000`; the high-prefix ISI handler occupies `fff00400`. This avoids the separate high-prefix I-TLB miss vector at `fff01000`, which is not implemented by this profile.

The same effective instruction address faults and retries three times:

| Trigger | Prepared state | Expected ISI syndrome | Handler repair |
| --- | --- | --- | --- |
| Page PP | Supervisor key Ks=1, TLB PP=00 | SRR1 manual bit 4 (`08000000`) | Replace way 0 with PP=10 using CPU `tlbli` |
| Segment N | SR2.N=1, permitted TLB entry | SRR1 manual bit 3 (`10000000`) | Clear SR2.N with CPU `mtsr` |
| Guarded page | TLB WIMG.G=1, PP=10 | SRR1 manual bit 3 (`10000000`) | Replace way 0 with WIMG.G=0 using CPU `tlbli` |

Each event must save SRR0=`20000000` and the old MSR=`00000060` plus its syndrome in SRR1. Exception entry runs with IR=DR=0 and MSR=`00000040`. The handler records those values, repairs the pre-existing mapping or segment descriptor, and executes `rfi` to retry precisely the faulting fetch. Successful calls return 42, 73 and 100, proving that the corrected instruction was fetched and executed. The main program performs its initial and guarded page `tlbli` loads in real mode; handler repairs also execute in real mode.

The independent physical RAM responder delays instruction and data responses and retirement. It checks one protection and two guarded typed fetch-fault retirements, each at the alias PC with no architectural destination, along with four CPU `tlbli` retirements, twelve CPU BAT writes, physical probe fetches only after repair, and the page-protection/no-execute/guarded sticky diagnostics without miss/configuration/changed causes. The fixture cannot preload a TLB entry. This verifies resumable instruction-page denials using the existing ISI carrier, not I-TLB miss entry, page-table walking, or frontend coherence.

Build with the pinned container toolchain, then run strict Verilator:

```sh
docker run --rm --user "$(id -u):$(id -g)" --volume "$PWD:/work" --workdir /work/toolchain ppc603e-cross:bookworm-20250811 make page-isi
python3 toolchain/run-rtl-smoke.py --profile page-isi --elf toolchain/build/page-isi/smoke.elf --build-dir toolchain/build/rtl-page-isi
```

Integrated acceptance on 2026-09-23 passed strict `-Wall --assert` Verilator:
**one PP ISI, two guarded ISIs (N and G), four CPU TLBLI operations,
twelve CPU BAT writes, 374 retirements and 4,492 cycles**. The passing log is
`/tmp/ppc-page-isi-fw.log`.

A negative control changes only a temporary memory image. It verifies the
handler `tlbli r11` word `7c005fe4` at `fff00468`, replaces it with `isync`
`4c00012c`, and leaves the canonical ELF and image untouched. The harness
rejects the second protection fault at cycle 1,893 with `unexpected PP fault
order` and fault PC `20000000`; it does not time out or report success. The
negative log is `/tmp/ppc-page-isi-negative.log`. Router sticky `fault_ea` can
refer to a younger canceled fetch within the same page, so the harness checks
its page identity while requiring the exact fault PC in the retired packet and
SRR0. These logs are temporary local artifacts.
