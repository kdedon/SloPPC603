# Execute-stage restructure (step B)

Step B of the [result bus restructure](RESULT_BUS_RESTRUCTURE.md). It moves
integer arithmetic one cycle earlier, into the cycle after dispatch, and
registers the result at the edge where the IU now captures its inputs. Every
post-execute event then starts from a flop, at the edge it uses today, so
the cycle counts in [STAGE_TIMING.md](STAGE_TIMING.md), the
[execution edge table](EXECUTION_CONTRACT.md#current-finish-and-retirement-edges)
and `sim/spec/stage_timing.json` do not change.

## Today

Edges follow [STAGE_TIMING.md](STAGE_TIMING.md#precise-implementation-events):
D is the atomic CQ/rename/station capture, E the station→IU issue edge
(`issue_valid && issue_ready`), F the CQ finish acceptance.

| Interval | Now |
|---|---|
| `[D, E=D+1)` | station holds the op; operands may be completed by a wake |
| E | IU input register (`held`, `ppc_iu.sv`) captures the issue packet |
| `[E, E+1)` | ALU computes from `held`; in the same cycle the result drives CQ finish, head retire, rename wake, station issue of a dependent, LSU P1 base snoop and EA adder, CR forward → branch resolve → fetch target → I-µTLB |
| F = E+1 | finish, wake capture, dependent issue, commit of a ready head (`finish_to_retire_min=0`) |

The interval `[E, E+1)` holds the ALU and the whole post-execute cone in
series. That is the 44.5 MHz path.

## Step B

The station entry is already the operand register: D captures it, and its
bypass selects for an IU producer are registered at capture (`bypass_a/b`
in `ppc_dispatch.sv`). Step B computes from it.

| Interval | Step B |
|---|---|
| `[D, D+1)` | ALU computes from the station entry (plus a forwarded operand, below): the manual's E cycle, "operands latched at the end of dispatch" (§6.2, PDF 250 / 6-4) |
| E = D+1 | the issue edge registers the result (`value_q`, `cr0_q`, `ca_q`, `ov_q`, `so_q`) instead of the inputs |
| `[E, E+1)` | finish, retire, wake, CR forward, branch resolve, LSU P1 snoop and fetch redirect run from those flops |
| F = E+1 | unchanged |

The edge names keep their current meaning: E is the issue handshake, F the
finish acceptance. Only the arithmetic moves from `[E, E+1)` to `[E-1, E)`.

## Manual-visible edges

| Event | Today | Step B | Why it holds |
|---|---|---|---|
| Dispatch | D | D | station capture unchanged |
| Issue (ready op) | E = D+1 | E = D+1 | same handshake; it now loads the result flops |
| Execute, one-cycle forms (Table 6-4, PDF 270–271) | `[D+1, D+2)` | `[D, D+1)` | one ALU cycle either way; now adjacent to dispatch as §6.2 reads |
| Finish | F = D+2 | F = D+2 | the result is offered during `[E, E+1)` from flops |
| Commit / writeback / release (TD-03, TD-04, TD-05) | ≥ F, ready head at F | same | retire reads the CQ head and the offered result, now a flop |
| Dependent integer op, back to back | issues at producer F, executes `[F, F+1)` | issues at producer F, executes `[F-1, F)` from the forwarded flop, its result flop loads at F | the dependent's issue edge and finish edge are unchanged: one cycle per dependent link, §6.3.3, PDF 257–258 |
| Branch on a CR from the IU (Figure 6-5, resolve 5E, target 6F) | CR valid during `[E, E+1)`, combinational off the ALU | CR valid during `[E, E+1)` from `cr0_q` | resolve in the same cycle; with `MISPREDICT_FETCH_NOW` the target request still leaves in that cycle, now from a flop |
| Load-use (UM 6.4.4, 2-cycle) | load result `r_q` → station → `held` at F | `r_q` → station mux → ALU → result flop at F | the pipelined LSU result is already a flop; edges unchanged |
| Store data, LSU base from an IU result | snoop during `[E, E+1)` | same interval, from the flop | unchanged edges |
| Multiply, divide | engines start at E, result offered from `held` | unchanged | the engines keep their own registers and latency |
| SRU add/compare (second station) | as the IU | as the IU | same `ppc_iu` instance with `ADD_COMPARE_ONLY` |

No event changes edge, so the stage-timing probe, `test-core-*-timing`
benches and the reference comparisons are the acceptance check: with the
parameter on they must pass unmodified.

## The new single-cycle loops

1. **Result flop → forward mux → ALU → result flop.** The station's
   `select_operand` is an AND-OR mux whose IU select is the registered
   `bypass_a/b`; its LSU and SRU legs compare a registered producer tag
   against the offering unit's registered producer. The data leg is one
   4:1 AND-OR level ahead of the adder/rotator. This is the classic EX→EX
   bypass of a five-stage pipeline.
2. **Issue enable.** The result flops load on `issue_valid && issue_ready`.
   `issue_valid` carries `rs_cancel`, which depends on branch resolve from
   `cr0_q`. Data flops should load on the IU's free condition alone
   (`!occupied || result accepted`), with only `occupied` taking the
   handshake and cancel, so cancel stays off the 32-bit enable.
3. **Dispatch → capture.** Unchanged: `dispatch` already enables the
   station capture. Step B adds no dispatch term to the IU.

What leaves the critical path: the ALU in front of CQ finish, head retire,
rename wake, the LSU P1 EA adder and D-µTLB, and the CR → branch → fetch →
I-µTLB → I-cache chain. Each of these now starts at a flop.

What remains: the SRU result feeds the IU station's forward leg and the
IU result feeds the SRU's. With both units executing at E these are flop
starts. With only one converted, the other unit's ALU sits in front of the
converted unit's ALU, so both convert together under one parameter.

## Fit after step A

A matched CPU-only fit of step A (c887c01: hints, width 2, LSU pipe, no FPU,
seed 1, 66 MHz constraint) gave 41.64 MHz slow corner (−8.862 ns) and
24,569 ALMs, against 44.5 MHz and about 23.2k ALMs before. The worst
endpoints are CQ `generations_q` → LSU `sq_q[0].committed` and IQ entries →
LSU `p1_q[0].ea`. The fourth wake bus added a third base sum to P1's
same-cycle snoop, which costs more than the removed steering. Step B
therefore also covers the LSU and the CQ, and must not widen any
same-cycle forwarding mux.

### LSU P1 forms its EA from registers

Today a ready-base load adds base and displacement in the dispatch cycle
(dispatch cone → adder → `p1_q.ea`), and a waiting base adds every wake
bus to the displacement in parallel and selects late (wake → adder →
request address → D-µTLB).

Step B: dispatch captures into P1 the displacement, the base value when
ready, and otherwise a one-hot source select registered at dispatch: the
producing unit is known from the base's rename owner, and each unit now
has a fixed bus. In P1's own cycle the base is a registered-select mux of
flops (the P1 base register, the IU, SRU or LSU result flop), followed by
one adder, the request address and the D-µTLB. Only the access's valid
waits on the wake match; the address cone carries no compare. This is
the manual's LSU first stage, EA and translation in one cycle after the
operands are latched (UM 6.4.4).

Cycle counts:

| Case | Today | Step B |
|---|---|---|
| Ready base | EA formed in the dispatch cycle, captured at D | EA formed in `[D, D+1)`; the same offer edge only if today's access offers from `p1_q` in that cycle (to confirm with `test-core-lsu-timing` before B3a) |
| `addi`/`lwz` then a load on its base (Table 6-6, 2 cycles) | snoop sums the bus in the producer's result cycle | sums the producer's result flop in that same cycle: unchanged |
| Snoop removed, base read after writeback | — | 3 cycles: one more than Table 6-6 |

So removing the base snoop outright (the old `LSU_BASE_SNOOP=0` wait) does
not keep manual counts; forming the EA in P1 from a registered select does,
and it needs one adder instead of one per bus. The wake3 leg goes away as
a separate sum.

Implemented as `ppc_lsu_pipe` parameter `P1_EA`, set from `EXECUTE_AT_E`
(the bus legs are flops only when the units execute at E). Each P1 entry
holds its base in `ea` and its addend in `offset`; the head's EA is
`base + offset`, where the base is `ea` or, while it waits, the bus named
by `base_sel`. The core keeps a one-hot bus per completion entry
(`cq_bus_q`, written at allocation from the station or unit the
instruction goes to) and registers the base producer's at dispatch. A
base on another bus (a load the serialized lane adopts, which finishes on
the first bus) is captured, not summed, and the access offers a cycle
later. Alignment of a captured base still comes from a 12-bit sum at
capture, so `fast` stays registered. Ready bases offer from P1 at the same
edge as before.

Recorded: `lint`, `check-spec`, `test-dtlb-projection-composition`,
`test-lsu-*` and 24 core benches (recovery, dual, dual-lsu-pipe,
branch-recovery/-fold, lsu-timing, -snoop, -602, multiply-/divider-timing,
serialization, dcache-lsu-pipe, -projection-off, lsu-wake-wrap,
lsu-response-wrap, lsu-update, lsu-extensions, dq1-page-pipe/-native,
alignment, alignment-dependencies, add-recovery, memory-edges,
ctr-target-capture), commit 0b3e520, 2026-10-20. Width 1 and width 2
(`DISPATCH_WIDTH=2`), each with `EXECUTE_AT_E=0` and `=1`: all pass, and
every printed cycle count is equal between the two settings. MiSTer config
(`tools/verilate-lsu-pipe`, `BRANCH_REMOVAL=1`): 21 of 24 pass with both
settings and equal cycles; memory-edges and ctr-target-capture fail as on
the baseline, and dq1-page-native does not build under the pipe wrapper
(it redefines `PPC_LSU_PIPE`). `quartus_map --analysis_and_elaboration`
of `ppc603e_core` with `PPC_EXECUTE_AT_E=1`: 0 errors. No fit yet.

### CQ finish ownership from a register

`generations_q` → finish → head retire → store commit is the other worst
endpoint. A unit learns its producer at issue; the CQ can compare that
producer's ownership then and register an `owned` bit beside the result
flop. Ownership is lost only by an accepted kill, so finish acceptance
becomes `owned_q && !kill[index]` and the generation compare leaves the
retire and commit cone.

Implemented as `ppc_completion` parameter `OWNER_AT_LOAD`, set from
`EXECUTE_AT_E`. Six sources each report the edge their producer register
loads and the producer it takes: the IU (issue), the serialized lane
(dispatch, held-move issue or adoption of a load/store access), the SRU
(issue) and the load/store unit's result register (`result_load_o`, for
the third and fourth ports; a P2 retire or a replay from the miss queue).
At that edge the CQ evaluates the entry's post-edge state: allocated now
with this tag, or live, unfinished, of this generation, not killed and not
finished now. The bit then clears when that entry is killed or finishes on
any port. Finish acceptance, wake qualification and the head/CQ[1]
arrival matches use the bit; `pending_head` stays, as it is a flop
lookup. The generation compare remains as a per-port simulation assertion
whenever a source offers a result.

### Result flops load on unit free (B2)

With `EXECUTE_AT_E` the IU's `value_q`/flag flops load on
`!occupied || (result_offer_o && result_ready_i)`. Only `occupied` and
`held` take the handshake and the cancel. A killed IU op takes every
younger station op with it, so an issue never depends on the cancel to
free the unit; a simulation assertion checks it.

### Registered forward selects (B3)

`ppc_dispatch` parameter `REGISTERED_FORWARD` (set from `EXECUTE_AT_E`):
the load/store and second forward port selects compare the operand's
producer against each source's next producer (the D input of that
source's producer register: the IU or SRU issue packet on issue, the
load/store result load) and register the match. In the operand cycle the
select is `done && !ready && match_q`; the compare leaves the mux select.
A simulation assertion checks each registered match against the direct
compare while the station is occupied.

### Fit of B3a

Coordinator fit, CPU-only, matched to the step A fit, of 0d05b7f with
`PPC_EXECUTE_AT_E=1`: 45.19 MHz slow corner (setup −6.979 ns at 66 MHz),
23,923 ALMs; step A alone was 41.64 MHz, baseline aa89a0e 44.5 MHz. The
LSU P1 EA endpoint left the top paths. The new worst endpoint is
`ppc_iu:iu|held.ctrl.op[1]` → `route_managed_q`: the IU result and CR
reach branch resolve and the fetch/router through a `held`-decoded
select (the multiply/divide result mux keys on `held.ctrl.op`). Next
step: move BPU resolve and the fetch redirect onto the registered result
(register the long/short select at issue so `cr0` is a flop, then cut
resolve → fetch), before B4.

## Recovery and ownership

The result flops belong to `held`'s producer and are qualified by the same
`occupied` bit; `cancel_i` clears it at the accepted kill as today. Wakes
no longer carry the CQ kill term (step A), so a killed producer's flopped
result may wake younger consumers on the kill edge; those consumers die by
the same kill vector and rename rebuilds from survivors.

## Files and order

| Step | Change | Files | Test |
|---|---|---|---|
| B1 (done) | `EXECUTE_AT_E` in `ppc_iu`: single-cycle datapath reads `issue_i`, result registered at issue; multiply/divide form their result from `held` and the engines; core parameter passes it to the IU and SRU | `rtl/ppc_iu.sv`, `rtl/ppc_core.sv`, `sim/Makefile` | lint both settings; focused and core benches off and on |
| B2 (done) | Result flops load on the IU free condition; `occupied` keeps the handshake | `rtl/ppc_iu.sv` | `test-execution` backpressure cases |
| B3 (done) | Station LSU/SRU forward selects registered at capture/wake, like `bypass_a/b` | `rtl/ppc_dispatch.sv` | `test-dispatch-*`, core LSU and dual benches |
| B4 | Stage-timing bench samples the result flops for the trace's value; TD-02 and STAGE_TIMING state the step B intervals | `tb/tb_stage_timing.sv`, `docs/TIMING_DECISIONS.md`, `docs/STAGE_TIMING.md` | `test-stage`, `check-spec` |
| B5 | Default on; fit the CPU-only and MiSTer tops | `rtl/ppc_core.sv` | full gate by the coordinator |
| B3a (done) | LSU P1: displacement, base value or registered bus select at dispatch; EA, request address and D-µTLB in P1's cycle from flops; drop the per-bus snoop sums | `rtl/ppc_lsu_pipe.sv`, `rtl/ppc_core.sv` | `test-core-lsu-timing-snoop`, `test-core-lsu-*`, `test-core-dcache-lsu-pipe`, MiSTer config |
| B3b (done) | CQ registers the finish ownership check at each source's load edge | `rtl/ppc_completion.sv`, `rtl/ppc_core.sv`, `rtl/ppc_lsu_pipe.sv` | `test-completion*`, `test-recovery-*` |
| B6 | Retire `MISPREDICT_FETCH_NOW=0` and `LSU_BASE_SNOOP=0` if the fit shows the flop-start chains meet 66 MHz | `rtl/ppc_core.sv` | branch and LSU timing benches |

Each step keeps the parameter off by default until B5, so main stays green.
TD-02 changes only at B4, after the bench evidence.

## Area

The IU gains 41 result flops and a small multiply/divide result former
(value select, overflow, record flags); the SRU 41 flops. The input
`held` register stays for the engines. Under 200 ALMs before a fit.
