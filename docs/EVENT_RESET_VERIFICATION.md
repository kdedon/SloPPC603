# Event/reset focused verification

This test-only round passed on 2026-09-21. Production RTL is unchanged.
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

The gate passed with exit0 from `21:38:12.915202Z` to `21:38:59.759002Z`:

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

All 144 gate source/build inputs stayed unchanged. All production RTL and its
manifest also match the separate pre-round snapshot.

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

- Original timer SHA256: `cf9ed8835f84e70da53a23dd5dd6d133da27e22b14ee2335b4d68733d2e10daf`.

To reproduce from the repository root without modifying repository sources:

```sh
python3 - <<'PY'
from pathlib import Path
import resource, subprocess, tempfile
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
work = Path(tempfile.mkdtemp(prefix='ppc-event-reset-negative-'))
source = Path('ppc603e/rtl/ppc_timer.sv').read_text()
old = "      decrementer_o <= 32'hffff_ffff;\n      decrementer_pending_o <= 1'b0;\n"
assert source.count(old) == 1
mutant = work / 'ppc_timer.sv'
mutant.write_text(source.replace(old, "      decrementer_o <= 32'hffff_ffff;\n", 1))
rtl = [str(Path('ppc603e/rtl') / line.strip())
       for line in Path('ppc603e/rtl/files.f').read_text().splitlines()
       if line.strip() and not line.lstrip().startswith(('#', '//'))]
rtl[rtl.index('ppc603e/rtl/ppc_timer.sv')] = str(mutant)
subprocess.run(['verilator', '--binary', '--timing', '--assert', '-Wall',
    '--top-module', 'tb_core_event_reset', '--Mdir', str(work / 'obj'),
    *rtl, 'ppc603e/tb/tb_core_event_reset.sv'], check=True)
r = subprocess.run([str(work / 'obj/Vtb_core_event_reset')],
                   capture_output=True, text=True, timeout=30)
output = r.stdout + r.stderr
print(output)
assert r.returncode != 0 and 'stale pending/event after reset' in output
PY
```

The reproduction omits the explanatory comment used in the recorded temporary
mutant, so its text hash differs while the injected defect is identical.
