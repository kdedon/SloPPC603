# Local HDL and verification conventions

Project-specific rules that apply on top of the shared `hdl-coding-guidelines` skill in [`skills/`](../skills/README.md). Where the two disagree, these conventions win. [AGENTS.md](../AGENTS.md) describes the overall workflow.

- Use SystemVerilog with a single `always_ff` owner for each state element and nonblocking sequential assignments. Use `always_comb` with defaults for combinational outputs; avoid inferred latches.
- Use typed packets, explicit signal direction suffixes, sized constants/casts and explicit signedness. Translate PowerPC manual bit numbering into HDL slice numbering in comments at nontrivial encodings.
- Keep architectural state separate from speculative values. Issue/finish/commit/flush acceptance must be explicit. Resource allocation is atomic and backpressure cannot drop transactions or change a stalled payload.
- State reset polarity, sampling and memory-transaction cancellation requirements at module boundaries. Do not reset large inferred RAMs merely to produce deterministic test values; reset validity metadata where sufficient.
- Shared physical pins require explicit direction/output-enable handling. Abstract valid/ready transports cannot be called 60x-compatible. Clock-domain boundaries and external signal synchronization must be explicit.
- Queue sizes and CPU capabilities belong in reviewed definitions; avoid unchecked magic widths or truncation. Unsupported modes/instructions must reject explicitly instead of retiring success through placeholder logic.
- Preserve an explicit compilation order in `rtl/files.f`. Run strict Verilator RTL lint with no blanket warning suppression. Any local waiver needs a narrow location and a reason; testbench-only procedural conventions must not hide RTL warnings.
- Feature tests check architectural/protocol requirements independently of implementation: adverse timing, finite resources, wraparound, stale completion after flush, exception ordering and reset. Record deterministic seeds and first-divergence diagnostics where randomized testing is used.
- Record actual build/tool versions and distinguish lint, simulation, synthesis, fit and static timing results. A green lint run is not evidence of FPGA fit or processor conformance.

Changes to these conventions follow the ordinary task review. Existing user authorization to implement the CPU covers routine fixes and validation; this document does not add an approval gate.
