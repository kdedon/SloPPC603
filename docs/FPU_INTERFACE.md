# Standalone FPU interface

The FPU accepts one instruction word at a time and holds its result until the core commits or aborts the exact `ppc_pkg::completion_tag_t` identity (3-bit queue index plus 8-bit generation). This serialized first implementation targets complete instruction semantics but has at most one FP instruction in flight. Matching the 603e's four-FPR-rename capacity and throughput needs a four-entry destination-owner table, source forwarding, and concurrent completion packets; no opcode or status policy should change. [UM §6.3.3.1, PDF 258 / 6-12; `FPU_CONTRACT.md`]

`ppc_fpu_pkg.sv` defines a typed arithmetic request (`op`, `a/b/c` raw 64-bit FPR values, RN, NI, VE/OE/UE/ZE, single-result flag) and response (raw 64-bit result, nine distinct invalid causes, OX/UX/ZX/XX, FR/FI/FPRF with validity, result-write suppression). XE stays in the shell's FPSCR logic. It also defines an instruction packet (`completion_tag_t`, 32-bit instruction, 32-bit GPR base/index, MSR FP/FE bits), a held result packet (tag, exception kind, proposed FPR/CR/base updates and fault context), and a memory packet (tag, EA, size, read/write, data). The arithmetic backend owns numeric classification/rounding; the shell owns architectural FPSCR sticky/summary, status instructions, CR effects, FPR storage, decode and commit. [UM §§2.3.4.2–3, PDF 103–113; PEM §§2.1.3–4, 3.3, PDF 68–72, 123–150]

The shell's `issue_valid/issue_ready` handshake captures instruction, tag, GPR values and MSR controls. `result_valid/result` stays stable while waiting for completion ownership. A matching `commit_valid/commit_tag` accepts only the held result; `abort_valid/abort_tag` or `kill_all` discards it. Index and generation must both match. A wrong-generation commit, abort, memory response or arithmetic response cannot update FPR/FPSCR, publish a store, or release the held instruction. `kill_all` clears pending work at recovery/reset. Result fields are **proposals**; the core may apply CR/base updates only when `commit_valid && commit_ready`, never from `result_valid` alone. Every architectural FPR/FPSCR update occurs on accepted matching commit. [UM §6.3.3, PDF 258 / 6-12; §4.5.7.1, PDF 188 / 4-30; `FPU_CONTRACT.md` exception disposition]

For loads the shell issues a tagged, word-aligned, atomic memory preparation request and waits for a tagged response carrying full 32/64-bit raw data or a fault. The LSU performs transport/translation and returns a single prepared result; the FPU widens `lfs` numerically or copies `lfd` bits. A killed response is ignored. For stores the shell calculates raw `stfs`/`stfd`/`stfiwx` data and sends a tagged **side-effect-free** preparation request at issue. The LSU must check translation, protection, alignment and transport feasibility and return prepared success or fault before the FPU publishes a result. Only after successful preparation does a matching commit drive the authorized store descriptor. `store_valid` and `commit_ready` then handshake on the same edge as `store_ready`; the core must hold `commit_valid` and its tag stable until `commit_ready`. Fault/kill suppress both the store and update-form GPR base change. The core commits any load/store update-form GPR base value alongside FPU commit. The LSU must keep a 64-bit operation atomic over its 32-bit transport. [UM §§2.3.4.3.8–10, 4.5.6, PDF 112–113, 184–186; PEM §3.3.4, PDF 130–131]

Illegal encodings report `FPU_ILLEGAL` before the MSR[FP] check; valid disabled FP instructions report `FPU_UNAVAILABLE`. Neither starts arithmetic or memory access. [UM Table 4-2, PDF 166 / 4-8; §4.5.8, PDF 189 / 4-31] The selected enabled-exception rule is `(FE0|FE1)&FEX` and precise completion, as recorded in `FPU_CONTRACT.md`; the shell calculates FPSCR effects from backend metadata then reports the exception in its held result. Reserved fields and unimplemented `fsqrt/fsqrts` are illegal. [UM Table 4-1, PDF 163 / 4-5; §§4.5.7–8, PDF 187–189; Table B-1, PDF 407]

The core maps the result's exception enum to its exception controller; the FPU
does not redirect instruction fetch or write SRR0/SRR1. Vector offsets below
are combined with the core's exception-prefix policy. [UM Table 4-1,
PDF 162–163 / 4-4–4-5]

| Result exception | Core disposition |
| --- | --- |
| `FPU_NO_EXCEPTION` | Commit the proposed state normally. |
| `FPU_ILLEGAL` | Program exception, offset `0x00700`, illegal-instruction cause. |
| `FPU_UNAVAILABLE` | FP-unavailable exception, offset `0x00800`. |
| `FPU_ALIGNMENT` | Alignment exception, offset `0x00600`. |
| `FPU_MEMORY_FAULT` | Route the returned LSU fault code/context through the core's data-fault path. |
| `FPU_FP_ENABLED` | Program exception, offset `0x00700`, FP-enabled cause; preserve the contract's proposed FPSCR/result disposition. |

The arithmetic backend module is `ppc_fpu_arith`. Its request and response follow `valid/ready`; response also returns the request tag, and responses with other tags are ignored. It must cover add/subtract/multiply/divide, fused multiply-add variants, `frsp`, `fctiw(z)`, compare, `fres`, and `frsqrte`. It may take multiple cycles, but holds its response under backpressure. The F1 `ss_fpu_candidate` remains an isolated experiment and is not a production dependency. [UM Tables 2-14–17, PDF 104–105; `FPU_REUSE_ASSESSMENT.md` F1–F4]

The core must deliver the same abort/kill identity to any LSU preparation
resources it allocates. The FPU discards its local instruction and drains stale
replies; it does not own the LSU's reservations or store-buffer entries. Keep
prepared translation/authorization associated with the full completion tag
until matching store acceptance or cancellation.

The memory response channel also follows ready/valid: the LSU holds its packet until accepted. A matching reply presented in the request-accept cycle is backpressured until the shell enters its response state. Unrelated stale replies may drain immediately. This permits a combinational preparation response without losing it.

While reset is asserted, outward request/result/store valid signals and issue/commit readiness are inactive. In particular, resetting a held store prevents publication even if the integrating consumer remains ready. The memory response channel may drain cancelled replies during reset.

Memory packet `data` uses register bit order: the low 32 bits hold a word, and all 64 bits hold a doubleword. The integrating LSU owns byte ordering, bus beat order and memory attributes from the core's instruction context. It must return the complete logical value after any byte-order conversion, and must not expose an intermediate half-load or half-store through this interface.

The shell must pass strict Verilator lint with no blanket waivers. Numerical acceptance belongs to the arithmetic backend's independent bit tests; shell acceptance requires directed decode/legality, raw FPR bits, FPSCR masks/stickiness, matching and stale tags, backpressure, kill, memory faults, and commit-only update tests. Builds use blocking `make -j2` commands, then grep completed logs. [Repository `AGENTS.md`; `CODING_CONVENTIONS.md`]

## Implementation schedule and resource boundary

The first implementation uses `clk_i` only and active-low synchronous reset `rst_ni`; no derived clock or CDC. One pending instruction register holds its full tag, decoded operation and operands. One 32×64-bit FPR bank and one 32-bit FPSCR own architectural state; a single arithmetic request register and one held result packet bound the datapath. The controller states are idle, send-arithmetic, await-arithmetic, send-memory-prepare, await-memory, and result-held. Arithmetic latency is backend dependent, while simple bit moves and status operations are available after one registered issue stage. A store needs a side-effect-free prepare response before result-ready and one store-accept handshake with matching commit. The serialized profile has initiation interval at least issue-to-commit plus one cycle and does not claim the UM Table 6-5 timing. [UM Tables 6-5–6, PDF 272–275; §6.3.3.1, PDF 258]

`NI=1` has a narrow project policy until more 603e-specific status evidence is found: the backend calculates IEEE exception metadata and then replaces a denormal delivered result with signed zero. Tests must label its FPSCR status as this policy, not a proven silicon encoding. Memory `size_bytes` is literal 4 or 8; the LSU prepares an atomic operation and returns its own tagged `fault_code`/`fault_info` alongside `fault`. The FPU forwards that context without interpreting it. A store descriptor becomes valid only during an exact-tag commit handshake. [UM §2.3.4.2, PDF 103 / 2-25; §4.5.6, PDF 184–186 / 4-26–4-28]

`stfs` extracts a single-format representation directly from its FPR operand without invoking `frsp` or changing FPSCR; the source is expected to be representable as binary32. The current shell truncates discarded low bits for a source outside that precondition. Software requiring a defined rounded conversion first executes `frsp`. `lfs` widens the binary32 representation exactly. [PEM §3.3.4, PDF 130–131 / 3-24–3-25; PEM `stfsx`, PDF 640 / 8-228]

Recorded: `make -C sim -j2 test-fpu-shell`, commit `919b76e` plus the pipeline,
estimate and test changes committed as `c10d82b`, 2026-09-27: 833 checks passed.
See [production verification](../sim/fpu/PRODUCTION.md) for instruction,
status, memory, cancellation and retirement coverage. These tests exercise the
standalone interface; the integrating CPU still needs its own end-to-end tests.
