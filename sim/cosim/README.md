# P13a CSV inventory parser

This directory contains a standard-library-only parser and inventory CLI. It validates the observed DingusPPC integer, floating-point, and disassembly CSV grammars without executing or linking the C++ reference oracle. The JSON output contains source SHA-256 hashes, executable row counts, and field-count distributions; it deliberately does not copy the vector corpus. Parser objects retain each row's raw line and split fields for a future adapter.

From the workspace root:

```sh
python3 -m unittest discover -s ppc603e/sim/cosim -p 'test_*.py'
python3 ppc603e/sim/cosim/parser.py dingusppc/cpu/ppc/test \
  -o /tmp/dingusppc-csv-manifest.json
```

The default model metadata is `MPC603EV` / PID7v / PVR `0x00070101`; `MPC603E` selects the audited PID6 metadata. Model selection is closed to those two consistent mappings. The parser validates structural fields and numeric widths, but does not validate opcode legality, mnemonic spelling, FP source syntax or semantics, disassembly correctness, architectural state, timing, exceptions, endian modes, or TLB operations.

The separate P13b/P13c executable lane is documented in
[`../../docs/REFERENCE_RUNNER.md`](../../docs/REFERENCE_RUNNER.md).
Run `python3 ppc603e/sim/cosim/run_reference.py` from the workspace root to
compile original DingusPPC handlers and the real-core trace bench, compare all
architectural snapshots, and exercise mismatch/rejection cases. The parser
and its input grammar remain unchanged.

The opt-in P13d memory lane uses
`python3 ppc603e/sim/cosim/run_memory_reference.py`. It compares all 168
implemented forms using original handlers, full register snapshots and a
bounded flat big-endian RAM backend. Its mandatory-header v2 traces use
`compare_memory.py`; the existing 38-field v1 format stays unchanged.
