# P13a CSV inventory parser

This directory contains a standard-library-only parser and inventory CLI. It validates the observed DingusPPC integer, floating-point, and disassembly CSV grammars without executing or linking the C++ reference oracle. The JSON output contains source SHA-256 hashes, executable row counts, and field-count distributions; it deliberately does not copy the vector corpus. Parser objects retain each row's raw line and split fields for a future adapter.

From the repository root:

```sh
python3 -m unittest discover -s sim/cosim -p 'test_*.py'
python3 sim/cosim/parser.py ../dingusppc/cpu/ppc/test \
  -o sim/build/dingusppc-csv-manifest.json
```

The default model metadata is `MPC603EV` / PID7v / PVR `0x00070101`; `MPC603E` selects the audited PID6 metadata. Model selection is closed to those two consistent mappings. The parser validates structural fields and numeric widths, but does not validate opcode legality, mnemonic spelling, FP source syntax or semantics, disassembly correctness, architectural state, timing, exceptions, endian modes, or TLB operations.

The separate P13b/P13c executable lane is documented in
[`../../docs/REFERENCE_RUNNER.md`](../../docs/REFERENCE_RUNNER.md).
`make -C sim test-reference` compiles original DingusPPC handlers and the
real-core trace bench, compares all architectural snapshots, and exercises
mismatch/rejection cases. The parser and its input grammar remain unchanged.

The P13d memory lane, part of `regression`, runs with
`make -C sim test-reference-memory`. It compares all 168 implemented forms using
original handlers, full register snapshots and a bounded flat big-endian RAM
backend. Its mandatory-header v2 traces use `compare_memory.py`; the existing
38-field v1 format stays unchanged.

Every runner requires a `../dingusppc` checkout and tracks its latest commit;
`make -C sim reference-update` fast-forwards it and prints the new log range.
Runs print and record the DingusPPC commit and dirty state. `LAST_VERIFIED` in
`reference_checkout.py` is the last commit a full reference run passed on; when
HEAD differs, the runner prints the `git log` range to review if a comparison
breaks. DingusPPC is a comparison reference, not a source of truth: triage every
mismatch against the manuals. The Makefile builds the flat-RAM reference runner once
(`build_reference_runner.py`) and passes it and `$(VERILATOR)` to each runner.
With the default `XRAND=1` it also passes `--xrand-seed $(XRAND_SEED)`: the RTL
is built with `--x-assign unique --x-initial unique`, run with that seed, and the
manifest records it as `xrand_seed`. `XRAND=0` keeps the zero-initialized build.

`run_firmware_reference.py` (`make -C sim test-reference-firmware`, part of
`reference-acceptance`) runs compiled firmware images on the whole DingusPPC
CPU/MMU/exception core through `firmware_runner.cpp` and compares them with the
RTL benches; see [REFERENCE_FIRMWARE.md](../../docs/REFERENCE_FIRMWARE.md).

`run_machine_reference.py` (`make -C sim test-reference-machine` and
`test-reference-machine-mmu`) steps `machine_runner.cpp` in lockstep with the
demo SoC or package top through whole programs; see
[REFERENCE_MACHINE.md](../../docs/REFERENCE_MACHINE.md). Both runners share the
603e corrections in `reference_adapter.h`.
