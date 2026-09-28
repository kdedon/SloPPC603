# Load/store extensions verification

Recorded: `make -C sim -j2 ci`, merge of the load/store branch (`7f882bd`) onto
`2970961` plus uncommitted merge resolution, 2026-09-27. Pass after adding the
`lsu` firmware to `make -C sim coverage` (rerun separately, pass).

Contract: [LOAD_STORE_EXTENSIONS.md](LOAD_STORE_EXTENSIONS.md).

## Results

| Check | Target | Result |
| --- | --- | --- |
| Directed bench | `make -C sim test-core-lsu-extensions` | checks=3581, events=12, requests=130, stores=41, probes=4, partial retirements=64 |
| Decode | `make -C sim test-lsu-extensions-decode` | 13,703 checks; 17 XO mutations accepted as other forms, 83 rejected |
| Reference lane | `make -C sim test-reference-lsu` | 530 snapshots over all 12 forms, 431 requests, 220 stores, no DingusPPC mismatch |
| Compiled firmware | `make -C toolchain rtl-lsu` | checks=8,455,588, retires=120,681, partial=1,176, 257 three-byte writes, 17,784 ARTRY and 12,045 DRTRY in the coverage run |
| Negative control | `make -C toolchain rtl-lsu-negative` | Same image with the extensions off fails at the first `stmw`, as required |
| Full gate | `make -C sim -j2 ci` | 433 regression PASS lines, 231 + 28 + 15 Python tests, container firmware build, 28 compiled-firmware profiles |
| Coverage | `make -C sim coverage` | 76.0% of `rtl/` lines (1,317 of 1,734), 16 runs, 15 waived arms, none uncovered |

The directed bench covers split scalars and byte-reverse, multiples and strings
(register wrap, zero count), every reservation rule, alignment DAR/DSISR/SRR0,
DSI restart inside `stmw`, `lmw`, a split `lwz` and `lswi`, TLB-miss restart
inside `lmw` and `stswi`, page-cross alignment under DR=1, and an interrupt held
until a cracked `lmw` finishes. A mutation that keeps the reservation after
`stwcx.` fails it. The firmware ELF contains GCC-generated `lmw`/`stmw` and
`lwarx`/`stwcx.` atomics plus inline-assembly strings.

The first coverage run failed: nothing reached the new 2- and 3-byte strobe
shapes in `ppc_bus60x` (0110, 1110, 0111). Adding the `lsu` firmware to the
coverage runs reaches all three.

Fit: `./quartus/translated/build.sh --docker` on `d1824e5` (same RTL as the
merge) meets 50 MHz setup and hold at every corner; Fmax 61.40 MHz, 9,652 ALMs
([baseline](TRANSLATED_SYNTHESIS_BASELINE.md)).

## Not established

Atomic bus transfer types are not driven (`lwarx`/`stwcx.` use plain reads and
writes); multiple/string timing is not modeled against the 603e tables; no
data cache, so no reservation snooping; little-endian mode is out of scope.
