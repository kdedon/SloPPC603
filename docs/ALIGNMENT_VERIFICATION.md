# Alignment exception verification

The current core rejects non-naturally-aligned halfword and word accesses.
These tests verify precise exception routing at that existing boundary. They do
not claim the full 603e alignment-detection rules: ordinary big-endian unaligned
accesses may be split by the real processor. See UM §4.5.6.1, printed 4-27–4-28.

## Independent expected state

The expected exception state is derived from the local 1997 MPC603e/EC603e
User's Manual, Table 4-13, printed 4-27 / PDF page 185. The table was inspected
visually as well as extracted as text. PowerPC bit numbering starts at the MSB.

- SRR0 identifies the faulting instruction; DAR contains its effective address.
- SRR1's upper half clears and its lower half saves the previous MSR lower half.
- The alignment vector is `0x600`, with the existing MSR[IP] prefix selection.
- DSISR identifies instruction addressing form, operation and source/destination
  and base registers. The main bench uses sixteen literal instruction/syndrome
  pairs, rather than importing the RTL's syndrome helper.

The standalone exception-state test checks both vector prefixes, nonzero old
MSR values, the alignment-specific SRR1 mask, entry-state changes and held-result
backpressure. Unsupported event kinds 5–7 still reject without state changes.
The supervisor decoder test covers all 32 register operands for DAR/DSISR reads
and writes, disabled-profile rejection and reserved-Rc-bit rejection.

## Core scenarios

`tb_core_alignment.sv` connects the actual core to variable-latency instruction
and data responders. Its oracle observes external requests and accepted
retirement packets only; it does not read internal register arrays, CQ state,
exception state or the decoder. Handler instructions expose saved state and
copy architectural registers for checking through retirement results.

The enabled profile runs sixteen consecutive faults, exceeding CQ and rename
capacity, without resetting between events. It covers D-form and indexed word
and halfword loads/stores, signed loads, and update forms. Each event preserves
its original instruction and PC and marks the alignment event explicitly. The
handler reads DAR, DSISR, SRR0 and SRR1, observes the unchanged destination and
update base, and changes SRR0 to skip both the fault and a younger store.
There must be no data request anywhere in this sequence. An older arithmetic
instruction must retire before each fault. Every fault is held for at least
twelve cycles before accepted retirement, with a stable packet assertion.

A second sequence repairs the base in the handler and returns to retry LWZU.
The retried instruction must issue exactly one aligned load, return the expected
data and atomically commit its destination and updated base.

The disabled profile resets between the same sixteen fault forms and requires
an ordered terminal diagnostic, no data request and no destination/base effect.
Both profiles additionally run odd-address byte loads/store and aligned-halfword
loads; these must complete without faults, with exact byte lanes, request count,
values and sign extension.

## Run

```sh
make -C sim -j2 test-core-alignment test-core-alignment-disabled
make -C sim test-exception-state test-supervisor-decode
```

Both new core targets are included in `test`, `regression` and `all`, with
separate enabled/disabled build directories. Full-system compiled-handler
coverage is complementary to this independent directed oracle.

## Full regression acceptance

On 2026-09-21 at 04:38 UTC, `make -C sim -j2 regression` completed
successfully (exit 0). The aggregate reaches 156 named test targets, runs 19
strict RTL lint profiles, and includes 204 tool tests, 22 cosim tests and 15
recovery-model tests (241 Python unit tests). All 124 direct RTL testbench
profiles also passed strict pre-elaboration. The full log contains 183 PASS
summaries; that is a log-entry count, not an independent test count.

Focused alignment results in the complete run were 3,697 checks for the enabled
profile and 2,651 for the disabled profile. The exception-state fixture passed
99 checks and the supervisor decoder 1,614. Original-handler reference lanes,
cache/bus/MMU service tests, recovery tests and the older instruction suites all
completed. This gate does not include optional cross-compiler firmware runs or
Quartus fitting; those have separate evidence.

SHA-256 snapshots of 125 source files (`rtl/*.sv`, `tb/**/*.sv` and the
simulation Makefile) were identical before and after the successful run.

Earlier attempts exposed an incomplete generated compiler-header cache and two
older fixtures that did not consume the new retirement marker. The cache was
regenerated. Completion-update and stage-timing fixtures now assert that normal
and terminal-diagnostic packets do not acquire an alignment-event marker. The
successful full run above includes those checks; no failure was waived.
