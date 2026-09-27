# Standalone FPU interface

The standalone module is being rebuilt for original 603e and 602 instruction
latency and throughput. `parameter bit CPU_602=0` selects 603e; setting it to
one at elaboration selects 602. There is no runtime personality switch. The
architectural contracts are [603e](FPU_CONTRACT.md) and
[602](FPU_602_CONTRACT.md); the [pipeline design](FPU_PIPELINE_DESIGN.md)
defines the acceptance schedule. The current pipeline is under verification:
prior serialized results do not establish its completion.

The issue interface carries the core's full `ppc_pkg::completion_tag_t`
(3-bit queue index and 8-bit generation). Four FPR destination credits allow
independent instructions to overlap. Pending capacity is five instructions in
603e and four in 602. Results retire in order; forwarding can precede retirement.
[603e UM §6.3.3.1, PDF 258; 602 UM §§1.1.3.1.3, 6.3.2–4, PDF 45, 299–305]

`ppc_fpu_pkg.sv` defines a typed arithmetic request (`op`, `a/b/c` raw 64-bit FPR values, RN, NI, VE/OE/UE/ZE, single-result flag) and response (raw 64-bit result, nine distinct invalid causes, OX/UX/ZX/XX, FR/FI/FPRF with validity, result-write suppression). XE stays in the shell's FPSCR logic. It also defines an instruction packet (`completion_tag_t`, 32-bit instruction, 32-bit GPR base/index, MSR FP/FE/PR bits), a held result packet (tag, exception kind, proposed FPR/CR/base updates and fault context), and a memory packet (tag, EA, size, read/write, data). The arithmetic backend owns numeric classification/rounding; the shell owns architectural FPSCR sticky/summary, status instructions, CR effects, FPR storage, decode and commit. [UM §§2.3.4.2–3, PDF 103–113; PEM §§2.1.3–4, 3.3, PDF 68–72, 123–150]

The primary `issue_valid_i/issue_ready_o/issue_i` lane captures instruction,
tag, GPR values and MSR controls. The second lane
`issue1_valid_i/issue1_ready_o/issue1_i` supplies the immediately younger
instruction. It accepts only with the primary lane on the same edge; a pair
contains one FPU operation and one FP memory operation. A rejected second lane
may move to the primary lane next cycle. Resource reservations belong to the
FPU and LSU, independently of lane number. Status barriers cannot pair. These
are the concurrent shell's implementation requirements; the acceptance record
must establish them before integration.

 `result_valid_o/result_o` exposes the oldest completed instruction and stays
stable while it waits for completion ownership. The 603e's additional
`result1_valid_o/result1_o` exposes an eligible immediately younger load;
`commit1_valid_i/commit1_tag_i/commit1_ready_o` may retire it only together
with the primary head. Neither may fault, and the pair may contain at most one
FPR write and one CR write. The 602 retires one instruction per edge and leaves
second-retirement readiness inactive. These outputs present an ordered queue:
if only the primary head retires, its unaccepted successor moves to the primary
output. When neither retires, the exposed packets remain stable. The integrator
must track the accepted prefix, not treat the two lanes as independent queues.
[603e UM §6.6.1.3, PDF 268–269; 602 UM §6.3.2, PDF 299] A matching `commit_valid/commit_tag` accepts only the held result; `abort_valid/abort_tag` discards the matching instruction and younger work; `kill_all` discards all pending work. Index and generation must both match. A wrong-generation commit, abort, memory response or arithmetic response cannot update FPR/FPSCR, publish a store, or release the held instruction. `kill_all` clears pending work at recovery/reset. Result fields are **proposals**; the core may apply CR/base updates only when `commit_valid && commit_ready`, never from `result_valid` alone. Every architectural FPR/FPSCR update occurs on accepted matching commit. [UM §6.3.3, PDF 258 / 6-12; §4.5.7.1, PDF 188 / 4-30; `FPU_CONTRACT.md` exception disposition]

For loads the shell issues a tagged, atomic memory preparation request and waits for a tagged response carrying full 32/64-bit raw data or a fault. The LSU performs transport/translation and returns a single prepared result; the 603e FPU widens `lfs` numerically or copies `lfd` bits. The 602 retains raw binary32 `lfs` bits and checks `lfd` for exact hardware representation. The 603e rejects non-word-aligned FP accesses; the 602 permits unaligned FP loads, whose transport belongs to the LSU, but rejects non-word-aligned FP stores. [602 UM §2.2.3, PDF 104; §§2.3.4.3.8–9, PDF 127–129] A killed response is ignored. For stores the shell calculates raw `stfs`/`stfd`/`stfiwx` data and sends a tagged **side-effect-free** preparation request at issue. The LSU must check translation, protection, alignment and transport feasibility and return prepared success or fault before the FPU publishes a result. Only after successful preparation does a matching commit drive the authorized store descriptor. `store_valid` and `commit_ready` then handshake on the same edge as `store_ready`; the core must hold `commit_valid` and its tag stable until `commit_ready`. Fault/kill suppress both the store and update-form GPR base change. The core commits any load/store update-form GPR base value alongside FPU commit. The LSU must keep a 64-bit operation atomic over its 32-bit transport. [UM §§2.3.4.3.8–10, 4.5.6, PDF 112–113, 184–186; PEM §3.3.4, PDF 130–131]

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
| `FPU_EMULATION_TRAP` | 602 emulation exception, offset `0x01600`; suppress architectural writes. |
| `FPU_PRIVILEGED` | Program exception, offset `0x00700`, privileged-instruction cause. |

The additional 602 dispositions follow 602 UM §§4.5.7, 4.5.18, PDF 211–212,
221. SP/LT SPR accesses use the tagged issue path: `gpr_b` supplies `mtspr`
data, and the result's GPR proposal carries `mfspr` data. They require supervisor
privilege but do not require MSR[FP].

The arithmetic backend module is `ppc_fpu_arith`. Its request and response follow `valid/ready`; response also returns the request tag, and responses with other tags are ignored. It covers add/subtract/multiply/divide, fused multiply-add variants, `frsp`, `fctiw(z)`, compare, `fres`, and `frsqrte`. It holds its response under backpressure. The F1 `ss_fpu_candidate` remains an isolated experiment and is not a production dependency. [UM Tables 2-14–17, PDF 104–105; `FPU_REUSE_ASSESSMENT.md` F1–F4]

The core must deliver the same abort/kill identity to any LSU preparation
resources it allocates. The FPU discards its local instruction and drains stale
replies; it does not own the LSU's reservations or store-buffer entries. Keep
prepared translation/authorization associated with the full completion tag
until matching store acceptance or cancellation. A queue index may be reused
with a new generation, but the core must not reuse the identical full tag while
any cancelled backend or LSU reply bearing that identity can still arrive.
Generation wrap requires draining or otherwise proving those replies impossible;
a receiver cannot distinguish two transactions with identical identifiers.

The memory response channel also follows ready/valid: the LSU holds its packet until accepted. A matching reply presented in the request-accept cycle is backpressured until the shell enters its response state. Unrelated stale replies may drain immediately. This permits a combinational preparation response without losing it.

While reset is asserted, outward request/result/store valid signals and issue/commit readiness are inactive. In particular, resetting a held store prevents publication even if the integrating consumer remains ready. Memory-response readiness is also inactive during reset or global kill; stale replies may drain after reset releases.

Memory packet `data` uses register bit order: the low 32 bits hold a word, and all 64 bits hold a doubleword. The integrating LSU owns byte ordering, bus beat order and memory attributes from the core's instruction context. It must return the complete logical value after any byte-order conversion, and must not expose an intermediate half-load or half-store through this interface.

The shell must pass strict Verilator lint with no blanket waivers. Numerical acceptance belongs to the arithmetic backend's independent bit tests; shell acceptance requires directed decode/legality, raw FPR bits, FPSCR masks/stickiness, matching and stale tags, backpressure, kill, memory faults, and commit-only update tests. Builds use blocking `make -j2` commands, then grep completed logs. [Repository `AGENTS.md`; `CODING_CONVENTIONS.md`]

## Implementation schedule and resource boundary

The module uses `clk_i` and active-low synchronous reset `rst_ni`. The
architectural FPR bank has 32 entries of 64 bits for 603e or 32 bits for 602;
FPSCR is 32 bits in both. The 602 additionally owns SP/LT tag words. Inspect
ports expose committed state only. Pending instruction records retain source
bindings, raw arithmetic metadata, memory disposition and completion identity.
See the pipeline design for execution latency, initiation interval, response
credits and the external LSU timing boundary.

FP memory operations execute in the external LSU. Its adapter must enforce
these hit-path latency/initiation intervals, expressed in core cycles:

| Instruction family | 603e | 602 |
| --- | --- | --- |
| `lfs`, `stfs`, including indexed/update forms; `stfiwx` | 2 / 1 | 2 / 1 |
| `lfd`, `stfd`, including indexed/update forms | 2 / 1 | 3 / 2 |

The adapter controls request admission with `mem_req_ready_i` and returns the
atomic tagged response at the scheduled stage; misses and faults may delay it.
Core dispatch must also respect the LSU's reservation availability. The shell
accepts externally prepared responses and does not supply a cache or enforce
these physical LSU stages itself. Immediate-response mock tests establish the
transport protocol, not original-chip memory timing.
[603e UM Table 6-6, PDF 274–276; 602 UM Table 6-6, PDF 316–318]

The 602 SP/LT `mfspr` and `mtspr` operations execute in one and two cycles,
respectively, with architectural writes still restricted to matching commit.
These are IU/SRU register-transfer timings, distinct from the three-stage
floating-point status instructions.
[602 UM Table 6-2, PDF 312; Table 6-5, PDF 315–316]

`forward_valid_o/forward_o` and `forward1_valid_o/forward1_o` are one-cycle
speculative notifications with no backpressure input. The primary notification
prioritizes a ready CR update; the second preserves another ready result, such
as the load paired with a retiring compare. This prevents two retired entries
from losing one notification to a single output arbiter. Consumers capture both
valid outputs on the same edge. FPR and CR fields have separate write qualifiers: an FPR
may forward before the same instruction's CR1, which waits for older FPSCR
effects. Consumers must honor those qualifiers rather than assume exactly one
notification per tag. `mcrfs` supplies its CR update at retirement only. The
integrating core must capture relevant FPR/CR results
and discard them on recovery; it must never use forwarding to authorize an
architectural update. The backend's `finish_valid_o/finish_o` similarly exposes
the final arithmetic stage before its held response queue. Its raw metadata
must match the eventual response for the same full tag. These bypass paths are
part of the timing constraints, not false paths.

`NI=1` has a narrow project policy until more 603e-specific status evidence is found: the backend calculates IEEE exception metadata and then replaces a denormal delivered result with signed zero. Tests must label its FPSCR status as this policy, not a proven silicon encoding. Memory `size_bytes` is literal 4 or 8; the LSU prepares an atomic operation and returns its own tagged `fault_code`/`fault_info` alongside `fault`. The FPU forwards that context without interpreting it. A store descriptor becomes valid only during an exact-tag commit handshake. [UM §2.3.4.2, PDF 103 / 2-25; §4.5.6, PDF 184–186 / 4-26–4-28]

`stfs` extracts a single-format representation directly from its FPR operand without invoking `frsp` or changing FPSCR; the source is expected to be representable as binary32. The current shell truncates discarded low bits for a source outside that precondition. Software requiring a defined rounded conversion first executes `frsp`. `lfs` widens the binary32 representation exactly. [PEM §3.3.4, PDF 130–131 / 3-24–3-25; PEM `stfsx`, PDF 640 / 8-228]

Recorded: `make -C sim -j2 test-fpu-shell`, commit `919b76e` plus the pipeline,
estimate and test changes committed as `c10d82b`, 2026-09-27: 833 checks passed.
See [production verification](../sim/fpu/PRODUCTION.md) for instruction,
status, memory, cancellation and retirement coverage. These tests exercise the
standalone interface; the integrating CPU still needs its own end-to-end tests.

The historical serialized checkpoint `cb871b4` passed 851 shell checks. Its
measurements remain in [production verification](../sim/fpu/PRODUCTION.md) and
[Quartus evidence](../quartus/fpu-production/README.md). They do not qualify
the replacement concurrent shell, either 602 elaboration, or original-chip
latency and throughput. New acceptance records must identify the tested source
checkpoint. CPU attachment and fitted timing remain separate work.
