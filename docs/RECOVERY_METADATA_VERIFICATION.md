# Rename owner retention: focused acceptance

The reset/allocation-only owner-storage change passed focused validation on
2026-09-21 at `15:04:23.351183Z`. Independent review confirmed that every wake
and release still requires a valid slot and exact producer identity, reads still
use valid mappings, and recovery still rebuilds membership/readiness/maps from
the ordered survivors. Owner payload retention does not change those decisions.
No timing improvement is claimed: there was no new synthesis or fit.

## Meaningful added cases

The existing recovery-state fixture already checks wrapped/full CQ cuts,
same-edge retirement plus recovery plus surviving wake, youngest surviving WAW
mapping, stalled irrevocable heads, stale results, reuse and finite generation
wrap under the established cancellation contract. Existing update and fault
fixtures cover architectural writes, old-base addresses and cancellation.

`tb_recovery_storage.sv` adds five checks for the specific retained-stale-identity
risk: an old wake coincident with free-slot allocation, stale release against a
reused completed owner, exact release restoring architectural fallback, a stale
wake against an invalid slot, and another allocation/stale-wake collision
followed by the real new owner's completion. Expected readiness/values use the
public operand interface, not internal owner contents.

## Results and reproduction

Both commands passed with exit0:

```sh
make -C ppc603e/sim -j4 lint check-spec test-recovery test-recovery-select \
  test-completion-ring test-core-memory-edges test-core-lsu-update \
  test-core-alignment test-core-alignment-disabled test-core-alignment-dependencies \
  test-core-fetch-fault test-core-fetch-fault-disabled
make -C ppc603e/sim -j2 test-recovery-storage test-recovery-state test-recovery-execution
```

| Gate | Result |
| --- | --- |
| Strict RTL lint | 24 profiles |
| Python policy/checker/cosimulation tests | 241: 15 + 204 + 22 |
| Recovery selector | 245,760 exhaustive snapshot checks |
| Completion ring | 16,480 checks / 600 recovery scenarios |
| Recovery state / execution / storage | 5,871 / 1,066 / 23 checks |
| Memory edges | 799 checks |
| Load/store update program | 106,065 checks / 1,370 retirements / 202 reads / 72 writes |
| Enabled / disabled alignment | 3,697 / 2,651 checks |
| Alignment dependency cases | 634 checks / seven variants |
| Enabled / disabled typed fetch faults | 10,923 / 2,889 checks |

All 142 hashed RTL/TB/Makefile/RTL-manifest files stayed unchanged during the
focused run. Local evidence is `/tmp/ppc603e-owner-focused-summary.json`,
`/tmp/ppc603e-owner-source-before.json`, and
`/tmp/ppc603e-owner-source-after.json`. The identical before/after manifest
SHA256 is `d705d212a91803250fd7e475e9bf97992d2302ac3df1439ff869793bbd3c6d2a`.

- `/tmp/ppc603e-owner-focused.log` SHA256:
  `86f53fbf092ece065f3a5b89d532388fdc3c9a5b94517b217411f66b49569643`.
- `/tmp/ppc603e-owner-recovery.log` SHA256:
  `227941da7bb81e17868c4010bd4bca08330f457a16effeac3eda7ea07fbd8108`.
- `rtl/ppc_rename.sv` SHA256:
  `8f5b5b11de3906a0898f4f478117cbad7ce426867e9b327d8179d76e94007b16`.
- `tb/tb_recovery_storage.sv` SHA256:
  `02fadecfcd0018ad35c720eedde7d3600ce3b5b8a881386c086cf72921f16cd4`.

## Scope and remaining qualification

The [timer full regression](TIMER_VERIFICATION.md) passed **before** this owner
storage change. This limited final round deliberately ran the focused gates
above instead of repeating that full regression. Compiled firmware reruns are
recorded separately in [compiled acceptance](COMPILED_FIRMWARE_VERIFICATION.md).
The owner change has not received a fresh FPGA measurement; earlier timing
archives remain evidence of their own source manifests.

The tests do not make arbitrarily delayed stale tokens safe after complete
finite-generation wrap. Cancellation must obey the existing producer-lifetime
contract. Broader formal proof, full ISA differential validation and physical
clock/transport qualification remain outside this focused acceptance.
