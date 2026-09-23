# Current cached-physical synthesis baseline

This profile remains separate from the timer-enabled live-BAT measurement in
[TIMER_SYNTHESIS_BASELINE.md](TIMER_SYNTHESIS_BASELINE.md). The configurations
contain different memory integrations and must not be treated as an optimization
comparison.
The cached-physical top was not refitted during the later timer wave; the
results below identify the archived committed-EA revision, not a new measurement
of every subsequent source edit.

The 2026-09-21 committed-EA current-subset build **fits Cyclone V, but does not meet the
provisional 50 MHz timing constraints**. Quartus 17.0.2 completed synthesis,
fitting, assembly and TimeQuest successfully; compilation and evidence checks
returned zero and before/after source hashes match. This is current integrated
RTL evidence, separate from the preserved historical bootstrap fit.

## Accepted result

Target: `5CSEBA6U23I7`, seed 1, one compilation worker.

| Resource | Fitted result |
| --- | --- |
| ALMs | 13,661 / 41,910 (33%) |
| Registers | 17,015 |
| Block-memory data bits | 131,456 |
| M10K blocks | 15 / 553 |
| DSP blocks | 6 / 112 |
| Virtual / physical I/O pins | 494 / 0 |

The complete 512-by-256 instruction-cache data array occupies **13 M10K
blocks**, storing all 131,072 bits. The instruction queue uses the other two
M10Ks for 384 bits. No MLAB memory is used. These are actual fitted resources,
not estimates projected from the bootstrap. No RAM-style attribute or alternate
storage model was used to obtain cache inference.

| Corner | Setup slack (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | -4.951 | +0.299 |
| Slow 1100 mV, -40 C | -5.324 | -0.084 |
| Fast 1100 mV, 100 C | +6.511 | +0.163 |
| Fast 1100 mV, -40 C | +6.776 | +0.104 |

All illegal/unconstrained clock, input-port, input-path, output-port and
output-path counts are zero for both setup and hold. This establishes complete
coverage by the **provisional** constraints, not correct board constraints or
timing closure. The 20 ns clock and zero min/max virtual-I/O delays are a
measurement experiment. The virtual clock receives a ripple-clock warning;
physical clocking, external delays and a supported PID7v clock ratio still
require reviewed constraints. No board operating frequency is certified.

## Concrete timing follow-up

A read-only `quartus_sta --do_report_timing` query on the completed fit
returned zero and reproduced the reported slacks.

- Worst setup is an internal rising-edge register-to-register, full-cycle
  path at slow 1100 mV, -40 C: `core|completion|active_q[2]` to
  `core|special|ea_q[30]`, slack **-5.324 ns**. The trace crosses retirement
  tag selection, special commit matching, redirect/recovery, completion wake,
  rename wake matching, operand A selection, and the full-width special EA
  adder (`Add1`). The prior low-EA classification/`iq_ready`/map-valid chain
  is absent from this reported worst path. Alignment classification now uses
  committed registers structurally; the execution EA still uses forwarded
  operands. This observation does not claim all critical paths are removed.
- Worst hold is a virtual-input-to-register path from `rst_ni` through special
  result-valid and completion wake-value selection to `core|rename|values[4][6]`,
  slack **-0.084 ns** at slow 1100 mV, -40 C. Arrival is 5.906 ns against a
  5.990 ns clock requirement with zero input delay. The other three reported
  corners pass hold; this residual violation remains a reset-input data path.

The latest joint revision reduces worst setup deficit from **6.098 to 5.324 ns**
and improves minimum hold from **-1.400 to -0.084 ns**, but **both requirements
still fail**. Constraints remain unchanged. This is not an isolated causal A/B
experiment or a frequency certification. The physical clock/reset arrival
contract still needs review before selecting a hold remedy; no reset behavior
or timing exclusions were changed.

The next bounded setup review target is the full serialized special EA operand
path. Its safety must be established separately before extending the committed
operand substitution beyond alignment classification. The
[timing-change record](TIMING_CONTROL_PATH.md) gives tests and prior revisions.

## Retained implementation and boundary

`ppc_integrated_measure` directly instantiates
`ppc_core_cached_bus60x_managed`, with supervisor exceptions enabled and the
instruction cache initially disabled. Live context and external interrupts are disabled in this
physical cached wrapper. The separately simulated live BAT wrapper is not composed
with this FPGA measurement top. Runtime enable/invalidation controls retain
both scalar bypass and cached paths. The top exposes all 55 wrapper
port declarations: the complete retirement packet and backpressure, redirects,
maintenance, status and bus data/control/output-enable signals. It contains no
fixed instruction responder, tied-off data channel or folded retirement digest.
Arbitrary bus return data retains instruction and load datapaths.

The measured subset includes integer/control execution, selected supervisor
exceptions, instruction-cache maintenance, scalar 60x transport, line reads and
arbitration. It does not include integrated BAT/segment/TLB routing, general
precise exceptions, interrupts, decrementer, data cache, or complete software
cache-control semantics. The measurements do not certify the eventual MMU MVP.

## Reproduction and evidence

From `ppc603e/quartus/integrated`:

```sh
verilator --lint-only -Wall --top-module ppc_integrated_measure -f files.f
./build.sh --docker
./report-critical-paths.sh --docker  # requires the completed fit database
```

The build uses the pinned reviewed Quartus image, checks explicit virtual-port
coverage including packed-struct fields, records exact source/project/script
hashes before and after compilation, and rejects source drift. Report
collection requires fresh map/fit/STA/flow reports and zero physical I/O.

[Accepted evidence](../quartus/integrated/alignment-20260921/summary.txt) contains
resource excerpts, original STA/flow reports, critical paths, tool/image
identities, statuses and source hashes. The report-only query is reproduced by
`report-critical-paths.sh`; its shell command was run against the completed fit,
without rerunning synthesis or placement. Full raw reports/databases/bitstreams
remain ignored build products under `evidence/20260921T124834Z-224015` and
`output_files`. The accepted source hashes were verified again after the query.
The compact archive is self-verifiable with `sha256sum -c archive.sha256`
from its directory; its README distinguishes full-report provenance hashes
from bundled-file checksums.

Strict lint and shell syntax checks pass. The virtual-port checker rejects
both a missing final declaration and a vector wildcard incorrectly applied to
a packed struct. [Standalone cache evidence](../quartus/icache/accepted-20260921/summary.txt)
also records full-capacity readback, backpressure/cancellation tests, existing
cached-system suites and compiled big-endian firmware execution.

## Historical diagnostics

The bounded-ring revision is preserved in `quartus/integrated/ring-20260921`:
13,571 ALMs, 17,025 registers, -6.098 ns worst setup and -1.400 ns minimum
hold. Its complete corner results, path query and checksums remain unchanged.

The intermediate payload/FIFO control-cut revision is preserved in
`quartus/integrated/timing-20260921`: 13,541 ALMs, 16,979 registers,
-8.347 ns worst setup and +0.097 ns minimum hold. Its archive includes all
corner results and a self-checking archive manifest.

The first accepted integrated fit is preserved separately in
`quartus/integrated/accepted-20260921`, with its original source hashes,
13,985 ALMs, -12.576 ns worst setup and -0.774 ns worst hold. It is historical
evidence, not the current source revision.

The original bootstrap project and `quartus/evidence` remain unchanged. The
first current-system diagnostic exposed asynchronous cache reads that prevented
RAM inference; it was deliberately interrupted and remains explicitly labeled
in [its status record](../quartus/integrated/diagnostic-20260921/status.txt).
The synchronous-read cache implementation resolves that storage issue. Earlier
attempts with incomplete virtual-pin patterns were discarded as measurement
configuration diagnostics. Only the accepted source-stable, zero-physical-I/O
run above supplies the current fitted resource and timing results.
