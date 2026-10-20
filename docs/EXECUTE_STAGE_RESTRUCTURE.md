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
| B2 | Result flops load on the IU free condition; `occupied` keeps the handshake | `rtl/ppc_iu.sv` | `test-execution` backpressure cases |
| B3 | Station LSU/SRU forward selects registered at capture/wake, like `bypass_a/b` | `rtl/ppc_dispatch.sv` | `test-dispatch-*`, core LSU and dual benches |
| B4 | Stage-timing bench samples the result flops for the trace's value; TD-02 and STAGE_TIMING state the step B intervals | `tb/tb_stage_timing.sv`, `docs/TIMING_DECISIONS.md`, `docs/STAGE_TIMING.md` | `test-stage`, `check-spec` |
| B5 | Default on; fit the CPU-only and MiSTer tops | `rtl/ppc_core.sv` | full gate by the coordinator |
| B6 | Retire `MISPREDICT_FETCH_NOW=0` and `LSU_BASE_SNOOP=0` if the fit shows the flop-start chains meet 66 MHz | `rtl/ppc_core.sv` | branch and LSU timing benches |

Each step keeps the parameter off by default until B5, so main stays green.
TD-02 changes only at B4, after the bench evidence.

## Area

The IU gains 41 result flops and a small multiply/divide result former
(value select, overflow, record flags); the SRU 41 flops. The input
`held` register stays for the engines. Under 200 ALMs before a fit.
