# SDR1 CPU verification

Recorded: `make -C sim lint-sdr1 test-sdr1-decode test-core-sdr1 test-miss-derive`, commit pre-repository snapshot, imported in 3e727b6, 2026-09-23.
Recorded: `make -C sim test-core-sdr1`, commit this branch, 2026-09-26. Pass: 1,303 enabled and 43 disabled checks with the SDR1 write mask.

The strict gate is `make -C sim lint-sdr1 test-sdr1-decode test-core-sdr1 test-miss-derive` (2026-09-23). The independent decode matrix checks all 32 register fields across MFSPR, MFTB alias and MTSPR for SPR25, plus reserved Rc and neighboring selectors. It uses fixed complete-word anchors as well as the field generator; **705 checks** pass.

The actual-core oracle tests SDR1 reset/read/write with r0 as a real source. Written values carry nonzero reserved bits 16–22; readback and committed state must hold only HTABORG and HTABMASK (`0x12345678` reads `0x12340078`, `0xa1b2c3d4` reads `0xa1b201d4`, `0x1234` reads `0x34`). A real-mode write changes state only at matching retirement, holds unchanged under eight cycles of retirement backpressure, drains/refetches the next PC and supports the MFTB read alias. Killed writes and reads leave committed state and destination intact. Problem-state attempts of all three forms take the privileged exception before any CSR mutation. Writes while IR or DR is set become side-effect-free diagnostics; a translated-mode read remains allowed. A retained write accepts two successive redirect targets and resumes at the latest target after commitment. An external cut on the exact commit edge is rejected by the irrevocable boundary. The enabled core profile passes **1,303 checks**; the disabled profile retains terminal diagnostics.

This test verifies raw SDR1 storage and serialization. Encoding validation and PTEG derivation are tested separately; no page-miss exception or hash state is automatically installed here.
