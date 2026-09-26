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

Every runner requires `../dingusppc` to be a clean checkout of the commit pinned
in `reference_checkout.py`; `--allow-unpinned-reference` (or
`make REFERENCE_FLAGS=--allow-unpinned-reference`) overrides this and records the
actual commit. The Makefile builds the flat-RAM reference runner once
(`build_reference_runner.py`) and passes it and `$(VERILATOR)` to each runner.
