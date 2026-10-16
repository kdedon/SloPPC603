# CNTLZW record qualifier trial

Prepared against `3b94ab8`, 2026-10-15. The accepted CPU-only timing baseline
remains 40.99 MHz. This is a separate trial after reverting the slower raw-owner
projection; no frequency or correctness result is claimed before execution.

The cold baseline path runs from the IU count tree through CR0 and branch
qualification to station capture. CNTLZW's GPR result remains the actual
six-bit count, zero-extended to 32 bits. Only the internal value used to
derive CR LT/GT/EQ changes: source MSB1 gives zero; source MSB0 gives a
positive surrogate of one. An X/Z MSB retains the original count expression.
SO, write/compare priority, all result fields, unit handshakes, state and
ADD_COMPARE_ONLY behavior remain unchanged. No clocks, resets, pipeline stage,
latency or throughput contract changes; no new storage or memory ports.

The four-state argument depends on the actual procedural count tree. With a
known zero MSB its merges preserve a definite set count bit even when lower
source bits are unknown. A ternary rewrite of that tree would require review.
The optional proof pins actual package types and allows only this one arm
change in the full IU, then compares extracted candidate equations with frozen
original equations. Require 33 independently known counts, exactly 266,496
CR comparisons and nonzero changed-MSB0, MSB1, X/Z fallback observations.
Finite samples do not prove arbitrary temporal or ISA behavior.

Use the existing independent full-packet IU oracle at all four full/restricted
and 603e/602 configurations. It covers counts0..32, all control combinations,
one-cycle response, blocked results and cancellation. This is stronger than
adding another mirror-only IU bench. Also run lint/spec, unary/record execution,
CNTLZW recovery, exact stage timing, branch recovery/folding, retained CTR and
translated held-CR gates. Keep manual assertions unchanged. Follow with
Quartus17 compatibility and one matched capped CPU-only fit at66 MHz.
Record area, all setup/hold corners and unconstrained paths before adoption.

## Fresh focused checks

Recorded: `make -C sim test-cntlzw-record-projection`, commit `3b94ab8`
plus this uncommitted candidate, 2026-10-15. Pass: 33 independent known counts
and 266,496 CR comparisons. Coverage includes 154 changed MSB0 surrogates,
253 MSB1 cases, 252 X fallbacks and 252 Z fallbacks. The source guard accepts
only the reviewed record-arm delta and unchanged package/type contracts.

Recorded: the following serial command, same candidate and date. All pass;
no manual constants, acceptance tests or existing oracle equations change.

```sh
OBJCACHE= make -C sim -j1 lint check-spec test-iu-shift-record \
  test-execution test-unarylogical-execution test-record-execution \
  test-core-unarylogical test-cntlzw-recovery test-stage test-core-record-edges \
  test-core-branch-recovery test-core-branch-fold test-core-ctr-target-capture \
  test-core-translated-held-cr
```

Strict lint passes. Spec checks cover 190 rows, 41 rules, 391 source locators
and seven stage anchors; 259 tool tests and 29 bus-checker tests pass.

| Gate | Fresh result |
|---|---|
| Full IU, 603e and 602 timing profiles | 30,080 vectors / 180,480 independent packet checks each |
| Restricted IU, both timing profiles | 768 vectors / 4,608 checks each |
| Unary execution / record execution | 1,681 / 84 checks |
| Unary full core | 266,497 checks, 3,459 retirements, 10,847 cycles |
| CNTLZW recovery | 3,069 checks, including nonzero XER/CR and RS/IU/CQ cancellation |
| Stage timing | 14 retirements, exact dispatch schedule ending at cycle75 |
| Record-edge integration | 65 checks, including redirect/reset boundaries |
| Branch recovery | 102,359 checks, 1,324 retirements, 4,710 cycles |
| Branch folding, widths1/2 | 149,108 / 148,487 checks; 1,922 retirements in 8,918 / 7,806 cycles |
| Retained CTR capture, widths1/2 | 217,892 / 216,984 checks; 2,809 retirements in 13,054 / 11,998 cycles |
| Translated held CR, both widths | Taken owner/request191, dispatch196; not-taken dispatch193 |

Execution also retains 64 forwarding combinations and IU hold/turnover/reset
checks. The IU oracle checks held complete packets and cancellation, in
addition to the known arithmetic counts. Branch gates retain their required
capture/release/outcome coverage. These are focused candidate checks, not
full ISA/reference or release acceptance.

Recorded: pinned Quartus17 analysis/elaboration, same candidate and date:

```sh
. ci/pins.env
flock /tmp/ppc603e-sim.lock flock /tmp/ppc603e-quartus.lock \
  docker run --rm --network none --cpus 2 --memory 8g --memory-swap 8g \
  --user 1000:1000 --volume "$PWD:/work" --workdir /work/quartus/chip \
  "$QUARTUS_IMAGE_PIN" /opt/intelFPGA_lite/quartus/bin/quartus_map \
  ppc603e_chip -c ppc603e_chip --analysis_and_elaboration \
  --read_settings_files=on --write_settings_files=off
```

Pass: zero errors, 65 warnings, 22 seconds elapsed and 1,667 MiB peak virtual
memory. Project settings remain unchanged. Only `rtl/ppc_iu.sv` differs from
the accepted RTL baseline. No fitted frequency is attributed to this candidate
yet; full batch/reference acceptance and 66 MHz remain open.
