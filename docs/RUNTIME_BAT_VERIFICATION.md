# Runtime BAT directed verification

The opt-in CPU-programmable BAT path is checked at the service, router, decoder, and core boundaries. Run `make -C sim lint-runtime-bat` and `make -C sim -j5 test-bat-runtime-service test-bat-runtime-router test-core-runtime-bat test-core-runtime-bat-privilege test-runtime-bat-decode`. Both commands passed on 2026-09-22; lint uses strict `-Wall`, and simulations additionally enable `--assert`. These targets are also prerequisites of the ordinary `lint` and `test` gates. The compiled firmware evidence, including IRQ/DEC and a corrupted-readback negative run, is in [RUNTIME_BAT_FIRMWARE.md](RUNTIME_BAT_FIRMWARE.md).

| Suite | Passing checks | Publicly observed behavior |
|---|---:|---|
| `tb_bat_runtime_service` | 1,092 | All sixteen half-registers read back exactly. The prepared candidate remains private until commit. A commit changes it once and holds acknowledgment. Abort, coincident abort/prepare acceptance, held response, privilege/unsupported selector, malformed/reserved encodings, overlap, inactive staging, remap, and reset preserve the specified bank state. Translation confirms old/new physical addresses. |
| `tb_bat_runtime_router` | 52 | A held old memory offer and its physical response drain before CSR admission. Memory quiescence stays separate from CSR transaction idle. Startup access remains locked after start. Held prepare response and commit acknowledgment exclude reuse. Abort drains the response; a simultaneous context offer waits for CSR release. |
| `tb_core_runtime_bat` | 885 | Abstract service model checks no write before retirement, exact write/readback, retirement stall, delayed acknowledgment, held request cancellation, kill coincident with prepare acceptance, and kill in the result-publication cycle. Two retained recoveries change the resume target from `0x200` to `0x240`; the latter survives retirement, commit, and delayed acknowledgment. Reset at an offered request, prepared response, and delayed acknowledgment restarts cleanly. |
| `tb_core_runtime_bat_privilege` | 488 | CPU enters problem state through RFI, then MFSPR, MFTB read alias, and MTSPR BAT attempts each enter the Program vector with no CSR request or GPR read leak. |
| `tb_runtime_bat_decode` | 991,201 | Independent instruction encoding oracle covers the sixteen BAT selectors, MFSPR/MFTB read alias, MTSPR, Rc/reserved fields, feature profiles, and rejected encodings. It records 1,536 accepted and 1,536 rejected BAT cases. |

The service bench is a directed oracle for the public BAT response and translation pins. A temporary local mutant that wrote the committed upper/lower arrays on prepare tripped its bank-stability assertion; this demonstrates that the assertion detects an early write, but it is not independent proof of every validation path. The core bench models one outstanding CSR transaction and checks commit against the accepted retirement edge. It observes allocation identity for exact recovery stimulus; it does not force internal architectural state.

Coverage remains bounded. The direct core bench tests three reset points but not every possible request/response/acknowledgment edge combination. It exercises a retained cut while retirement is held, but does not independently force a killing cut against a previously offered retirement head; the CQ head-protection rule is covered in the existing completion/recovery regressions. IRQ/DEC persistence at a BAT write boundary is exercised by compiled firmware rather than this abstract core bench. These suites do not establish page-TLB refill, precise DSI, cache coherency, or physical bus timing.


## Final integration gate

The full pre-runtime `make -C sim -j6 regression` completed with exit status 0
on 2026-09-22. It includes the 24 existing strict RTL lint profiles, 243 Python
checks and the existing directed/reference/recovery corpus. The five new suites
and four additional runtime lint profiles passed separately after registration
in the Makefile. This run was started before their registration; a fresh ordinary
`regression` invocation now includes them as prerequisites.

All seven compiled firmware workloads pass; the runtime BAT workload was newly
compiled with the pinned offline toolchain and the prior six ELF files were
reused. The runtime readback-expectation negative fails with mailbox `81000212`;
the temporary early-write RTL mutant fails its bank-stability assertion.
See [RUNTIME_BAT_FIRMWARE.md](RUNTIME_BAT_FIRMWARE.md) for their exact scope.

Production RTL did not change during these acceptance runs. The final manifest
contains 233 RTL/test/spec/toolchain inputs, all unchanged from its capture to
completion. The initial 229-input manifest differed only by a runner docstring;
four new focused test files were added during verification.
No Quartus fit or timing analysis was run for this revision.
