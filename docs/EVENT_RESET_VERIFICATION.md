# Event/reset focused verification

Recorded: `make -C sim lint check-spec test-core-event-reset test-core-interrupt` and the focused gate below, commit pre-repository snapshot, imported in 3e727b6, 2026-09-21.

This test-only round passed on 2026-09-21. Production RTL is unchanged.

Recorded: `make -C sim test-core-event-reset`, commit this branch, 2026-09-26. Pass: 15,053 checks with special/CQ reset terms removed and the IRQ request registered (see [EVENT_RESET_CONTRACT.md](EVENT_RESET_CONTRACT.md)).

Recorded 2026-09-26: `make -C sim test-core-event-reset` passes 14,909 checks
on the audit-remediation branch (base 835f5c7 plus AUD-02/14 changes). The
oracle now expects the hard-reset MSR `0x0000_0040` (IP=1) from `mfmsr`, and
models RFI with reserved MSR bits masked.
[EVENT_RESET_CONTRACT.md](EVENT_RESET_CONTRACT.md) distinguishes immediate
suppression of handshake/event controls from architectural state clearing on an
active reset clock edge. This fixture checks controls while reset is sampled;
it does not establish board-level asynchronous assertion or release timing.

## Fixture and oracle

`tb_core_event_reset.sv` passes **14,909 checks across eight cases**: EXT and DEC,
each interrupted by reset at four stages:

1. An admitted event waiting for old accepted fetch/drain obligations.
2. Immediately after event acceptance.
3. Event context installation held without acknowledgment.
4. Context acknowledged, before handler-fetch redirect completes.

Each post-reset run retires 29 instructions and accepts exactly one deliberately
new event. The public oracle reads reset MSR/SRR0/SRR1, DAR/DSISR, XER, TBL/TBU
and DEC, with those registers seeded before reset. It then enables EE and
retires eight quiet instructions before requesting the new EXT or DEC. This
separates stale pending-event detection from successful later reuse. Handler
reads independently check saved PC/MSR, and RFI returns to the expected stream.

Architectural expectations come from an instruction/register model, retirement,
event traces and context handshakes. Only `dut.interrupt_admit` is observed to
choose the pre-event reset timing window. Context credits reject stray context
offers; forbidden store instructions detect stale execution/redirects; valid
and event-PC checks reject stale outputs. No internal state supplies expected
architectural values.

The direct-core fixture uses reset-aware, untagged instruction responses: their
old pending transactions are canceled by shared reset. It does not prove
immunity to an arbitrarily late pre-reset response arriving after a new request.
Reset cannot undo a store already accepted by a memory/device; this fixture
forbids stores rather than claiming rollback. Direct core results do not
establish BAT-wrapper restart, physical/cache reset or CDC. Masked-pending-only,
MTMSR-install-only and RFI-install-only reset cuts are not separate new cases;
the four cuts above are specifically asynchronous event-entry windows.

## Focused gate

```sh
make -C sim -j4 lint check-spec test-recovery \
  test-core-event-reset test-core-interrupt test-core-interrupt-disabled \
  test-timer test-core-timer-events test-core-timer-registers \
  test-core-live-context test-core-live-context-disabled test-exception-state
```

The gate passed with exit 0 from `21:38:12.915202Z` to `21:38:59.759002Z`:

| Fixture/gate | Result |
| --- | --- |
| Focused direct-bench strict prelint | 9 profiles |
| Aggregate strict RTL lint | 24 profiles |
| Python recovery/tools/cosimulation | 243 tests: 15 + 206 + 22 |
| New event reset | 14,909 checks / eight cases |
| Existing external IRQ enabled / disabled | 12,911 / 385 checks |
| Timer unit / events / registers | 210 / 15,031 / 4,833 checks |
| Live context enabled / disabled | 26,354 / 414 checks |
| Exception state | 204 checks |

Gate sources stayed unchanged during the run, and production RTL matched the
pre-round tree.

The new target is part of the regular `test` aggregate for future complete runs.
This round deliberately did not run the full regression, Quartus or compiled
firmware again. Earlier full/focused evidence retains its own source boundary.

## Negative control: stale DEC pending across reset

A temporary copy of `ppc_timer.sv` omitted **only** the pending-clear assignment
in the reset branch. The acknowledgment clear and all other logic were intact;
the real RTL and bench were unchanged. This mutant passed the four EXT cases,
then failed DEC/window0 after reset and EE enable, before fresh stimulus:

`stale pending/event after reset source=1 window=0 post=1 pc=0000002c cycle=71`

The process exited by SIGABRT (`-6`), not timeout. This demonstrates that the
post-reset no-stale-event oracle detects retained DEC pending state.

To reproduce from the repository root without modifying repository sources:

```sh
python3 - <<'PY'
from pathlib import Path
import resource, subprocess, tempfile
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
work = Path(tempfile.mkdtemp(prefix='ppc-event-reset-negative-'))
source = Path('rtl/ppc_timer.sv').read_text()
old = "      decrementer_o <= 32'hffff_ffff;\n      decrementer_pending_o <= 1'b0;\n"
assert source.count(old) == 1
mutant = work / 'ppc_timer.sv'
mutant.write_text(source.replace(old, "      decrementer_o <= 32'hffff_ffff;\n", 1))
rtl = [str(Path('rtl') / line.strip())
       for line in Path('rtl/files.f').read_text().splitlines()
       if line.strip() and not line.lstrip().startswith(('#', '//'))]
rtl[rtl.index('rtl/ppc_timer.sv')] = str(mutant)
subprocess.run(['verilator', '--binary', '--timing', '--assert', '-Wall',
    '--top-module', 'tb_core_event_reset', '--Mdir', str(work / 'obj'),
    *rtl, 'tb/tb_core_event_reset.sv'], check=True)
r = subprocess.run([str(work / 'obj/Vtb_core_event_reset')],
                   capture_output=True, text=True, timeout=30)
output = r.stdout + r.stderr
print(output)
assert r.returncode != 0 and 'stale pending/event after reset' in output
PY
```

The reproduction omits the explanatory comment used in the recorded mutant; the
injected defect is identical.

## Translated cached reset stress, 2026-09-27

Recorded: `make -C toolchain rtl-mmu-stress-cached`, commit 4428a5e, 2026-09-27.

The direct-core matrix above cannot reach the BAT router, the 60x bus or the
I-cache. The compiled MMU stress image covers them on
`ppc_core_bat_cached_bus60x`: eight seeded modes reset the CPU during a
miss-handler PTEG read or R/C write, a TLB load or invalidate, a translated
line fill, a held IRQ, a DEC entry or at random cycles, while EXT and DEC
fire throughout. Every mode passes the full image again from reset, with
matching handler and bench event counts and exact RFI resume PCs. See
[MMU_STRESS_FIRMWARE.md](MMU_STRESS_FIRMWARE.md).

