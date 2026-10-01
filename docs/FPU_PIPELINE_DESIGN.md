# Standalone FPU pipeline design

This is the implementation plan for replacing the serialized backend and shell.
It is not verification evidence. Both elaborations must meet the architectural
contracts in [FPU_CONTRACT.md](FPU_CONTRACT.md) and
[FPU_602_CONTRACT.md](FPU_602_CONTRACT.md), including original execution latency
and throughput. CPU integration remains separate.

## Compile-time personalities

`CPU_602=0` selects the 603e implementation; `CPU_602=1` selects the 602.
There is no runtime personality input. The 603e bank stores 32 binary64 words;
the 602 bank stores 32 binary32/raw words with architectural SP/LT tags. The
602 shell hands binary32 operands to the shared arithmetic in binary64 layout:
a normal, zero, infinite or NaN word takes its exact binary64 encoding, and a
denormal keeps a zero exponent field with its raw fraction, which the unpack,
divider and `frsqrte` read as an unnormalized significand scaled by 2^−126.
Widening therefore needs no leading-zero count. A written result is never a
binary32 denormal (underflow traps or delivers zero), so narrowing a result to
the stored binary32 word is a bit select. Software-emulated double operands
never enter hardware arithmetic as invented zero-filled values.

## Arithmetic execution

Execution starts when the arithmetic request handshake accepts an instruction.
Count that rising edge as zero. Without downstream stalls, response availability
must occur at edge 3 for ordinary operations, edge 4 for 603e double multiply or
fused operations, edge 18 for single divide and reciprocal, and edge 33 for 603e
double divide. Ordinary initiation interval is one cycle; 603e double multiply
and fused initiation interval is two. Divide and reciprocal block new arithmetic
issue until execution completes. Special operands retain their opcode's timing.
[603e UM §6.4.3, Table 6-5, physical PDF 264, 272–273;
602 UM §6.4.4, Table 6-5, physical PDF 305, 315–316]

The common datapath has multiply/alignment, add, and round/convert stages. Double
multiply uses two cycles in its multiply stage. Fused operations preserve the
exact product and cancellation bits until their one final rounding. Near/far
alignment optimizations require a numerical argument that discarded bits cannot
reappear after cancellation. Area or frequency pressure cannot justify extra
execution stages under this contract.

Response credits are reserved at acceptance. Four credits cover the standalone
rename capacity and guarantee completed packets survive downstream backpressure.
Responses preserve instruction order and full completion tags. Flush clears all
pipeline, divider, and response-valid state. Tests must cover simultaneous enqueue
and dequeue, held responses, full capacity, and recovery during every stage.

## Dispatch, forwarding, and retirement

The shell has two ordered dispatch lanes, `issue_valid_i/issue_ready_o/issue_i`
and `issue1_valid_i/issue1_ready_o/issue1_i`. Lane 1 can handshake only when
lane 0 handshakes on the same edge. A paired issue contains one FPU arithmetic,
move, or select operation and one floating-point LSU operation, in either lane
order. Status controls, tag SPR accesses, and 602 `fctiwz` serialize and cannot
pair. Queue space and rename credits are checked for the entire accepted prefix;
lane 1 failure does not revoke an accepted lane 0. The integrator may present an
unaccepted lane-1 instruction as lane 0 on the next edge. These lanes preserve
the manual's independent FPU and LSU dispatch opportunities without implying
the standalone FPU itself supplies the core's three-way general dispatcher.
[602 UM §§1.1.3.1.3, 6.3.2, 6.4.4–5, Tables 6-5–6,
physical PDF 45, 299, 304–305, 315–318]

The FPU and LSU each have an operand reservation opportunity, independent of
which dispatch lane supplied the instruction. A stalled arithmetic request must not
block a ready FP load or store, and an LSU request backpressure must not consume
arithmetic initiation bandwidth. Both resources publish full-tag completions
into the shared four- or five-entry pending queue. The 602 retires one oldest
instruction per edge. The 603e may also retire a following successful load when
the two results use at most one CR update and one FPR update; this includes a
compare plus load or an authorized store plus load. Same-edge retirement may
free queue slots and FPR rename credits for an accepted issue prefix. Pair tests
cover both lane orders, a waiting
producer with independent opposite-resource work, fault/abort of either lane,
and sustained FPU II1 concurrent with the LSU's externally prepared requests.
[603e UM §6.6.1.3, physical PDF 268; 602 UM §6.3.2, physical PDF 299]

The shell issue handshake represents dispatch. Operand reservation and backend
execution acceptance are distinct events; dispatch delay must not be counted as
an extra arithmetic execution stage or used to conceal excess execution latency.
Move/select capture operand bits and tags in one full-tagged FPU stage register;
the following stage computes the result while the next move/select may capture
its own operands. The shared stage is safe because a dispatch pair contains at
most one FPU instruction.
Ready independent instructions need a direct dispatch path when an obligatory
reservation cycle would prevent sustained issue with four rename entries.
The shell may decode and read a presented candidate before the late completion
credit decision; backend and LSU requests, pending records, and forwarding are
qualified by the actual accepted issue prefix. A held rejected lane produces no
execution or memory side effect.
Likewise, an arriving head result must be usable for retirement without an
unnecessary holding-register cycle. Acceptance tests cover the complete shell's
steady issue rate and dependent producer-to-consumer distance, not only the
backend's isolated latency.
The shell owns four FPR rename entries and pending instruction records. Each
source binds at dispatch to the pending slot of its youngest older producer
and keeps that binding until the producer retires, when the value is in the
register file; a slot is reused only after its producer retires. Completion
snooping updates waiting operands; rereading the architectural bank after a
stall cannot substitute for correct bindings.
[603e UM §6.3.3.1, physical PDF 258; 602 UM §§1.2.2.2, 6.4.3,
physical PDF 56, 304–305]

Pending capacity is five instructions for 603e and four for 602, selected at
elaboration. The 602 has four completion buffers and retires at most one
instruction per cycle. FPR rename capacity remains four in both builds.
[603e UM §6.3.3.1, physical PDF 258; 602 UM §§1.1.3.1.3, 6.3.2,
physical PDF 45, 299]

Finished FPR values and CR results are forwarded before architectural retirement.
Two forwarding packets preserve a same-edge CR result and load FPR result when
both 603e instructions retire together. A CR result takes the first forwarding
bus so the BPU can resolve the branch without waiting for retirement; the second
bus carries the remaining value. Each packet includes the full completion tag,
destination, value, validity, and 602 SP/LT tags where applicable. CR forwarding
excludes `mcrfs`. Architectural
updates remain exact-tag, in-order, commit-only. A held oldest result is stable;
independent younger instructions may execute and finish while it awaits commit.
[603e UM §§6.4.3, 6.6.1.3, physical PDF 264, 268]

Arithmetic stores raw exception and rounding metadata in pending records. At
ordered retirement, FPSCR effects combine with the committed FPSCR so concurrent
instructions cannot overwrite each other's sticky causes. Early Rc forwarding
must include relevant older pending status effects. FPSCR control instructions
serialize against older and younger FP instructions; speculative full-FPSCR
snapshots are insufficient unless rollback and intervening effects are proven.

An abort discards the matching instruction and younger work; stale responses
cannot match a reused entry by slot alone. Global kill flushes all execution and
pending state. Neither cancellation path publishes a store, changes FPR tags, or
updates architectural FPSCR/CR. Core-wide serialization and global retirement
order remain obligations of the eventual integration interface.

## Registered finish

The arithmetic unit's rounded result is registered in its response queue on
the finish edge. The only same-cycle use of the unregistered finish value is
a 2:1 operand mux directly in front of the arithmetic input and divider
registers, selected per operand (`req_fwd_i`). The 602 build also reads it
for its emulation-trap check on stores and forward notifications. Divide special-operand
classification reads the registered divider operands, one cycle after
acceptance, with an unchanged count.

Store data is not in the preparation packet. A store whose source finishes in
its preparation cycle marks its pending entry, which takes the formatted
value from the registered reply on the next cycle; the store descriptor reads
the reply directly if it is authorized in that cycle. Forward notifications
still appear on the finish cycle, from registered state; their payload
follows one cycle later from a register or, for a finishing result, from the
registered reply and the FPSCR prefix captured at the notification. A younger
CR1 result waits one cycle behind an older result announced in the same
cycle.

The mux selects come from a per-entry `finishing` bit, set one cycle early
from the unit's `next_finish_valid_o/next_finish_tag_o`. Readiness uses
`finish_write_o`, which depends only on registered state. A move or select
that captures a finishing operand marks it and substitutes the registered reply
in its second stage; a select whose selector is finishing waits for both
alternatives. Retirement, FPSCR, CR, FPR writes and pending capture read the
registered reply one cycle after finish; the previous RTL could retire on the
finish cycle itself. Same-edge retirement still frees queue and rename credits,
so sustained single-cycle issue is unchanged. The FPR-rename and barrier counts
are registered.

Execution latency is unchanged: dependent `fadd`, `fmr` and `stfd` distances
match the previous RTL (3, 3 and same-cycle store launch), and the forward bus
still announces results on the finish cycle.

A 602 source finishing with an emulation trap is ready for FPU consumers,
stores included: the trap aborts every younger instruction before it commits,
so a consumer that starts from the value never retires, and a store may
prepare its access (side-effect free) but never publishes. An `stfd` whose
source finishes in its preparation cycle checks the filled word for NaN,
infinity or denormal on the next cycle; that emulation trap outranks a
preparation fault. A preparation offered and not accepted stays offered with
its fields unchanged; when the source it then reads from a register traps,
the launch records the trap and the reply is ignored. An `stfd` whose source
is already in a register or the pending queue traps before any preparation,
as before.

## Pending queue

The pending queue is a circular buffer. Entries stay in their slots;
retirement advances a registered head, dispatch writes registered tail
slots, and cancellation or kill clears valid bits only. A registered matrix
records which slot is older than which; the oldest-reservation, pair-partner,
youngest-producer and forwarding picks and the abort mask use it directly.
Only head and second retirement read slots through the registered head.

An entry keeps its issue record, decode, effective address, disposition
flags, raw arithmetic status, and one 64-bit value word: the FPR result,
store data, fault information, proposed FPSCR or SPR read, by kind. Tags,
register indices and GPR update values come from the issue record, so a
result is stored once. Per-slot operand values, readiness and `fsel`
selector class form once and every source lookup picks a slot.

A waiting entry reads the producer slots bound at dispatch rather than
repeating the register compare. It also keeps its first lookup register (frS
for a load or store, else frA) and the `fsel` class of that register's
architectural value, refreshed by every register-file write, so a waiting
`fsel` decides readiness without reading the register file. The status and
value of a waiting entry, and every field of a free tail slot, are written
each cycle from their work context; only the valid, started and pipeline
flags wait for the dispatch and launch handshakes. Rename credits and the
barrier count follow retirement and dispatch; only an abort recounts.

A launching store records its raw source register; the head entry's store
descriptor applies the single, integer-word or 602 conversion. A finishing
producer's operand view selects the forward by its registered flag, and the
finishing write gates only readiness. Forwarded CR1 values and older sticky
causes read registered flags only; a finishing reply's flags reach just its
own trap and write checks. Dispatch admits one waiting entry per resource and
any other kind waits alone, so the pair partner is the waiting entry with an
older waiting one, formed beside the oldest pick (a simulation check asserts
the invariant). The divider loads its operands every idle or finishing cycle
and advances its datapath by state, so the start handshake reaches only its
state register.

`issue_ready_o` and `issue1_ready_o` are formed from registered state per
decode class. Queue space is "not full, or the head retires"; FPR credits are
"below the limit, or a retiring entry frees one". The lane decode, retirement
and abort terms enter last.

Fitted at `2ee1475` (both builds), the shell is off the 603e worst path. Its
worst register path is a pending entry's started flag into another entry's
value word through the launch and store-fill selects (−3.03 ns at 20 ns);
the add-stage exponent (−3.17 ns) and the divider's operand capture
(−2.52 ns) are the arithmetic limits. Fitted at `b14b066`, the 602 build
reaches 50.14 MHz (+0.056 ns) and the 603e 50.45 MHz (+0.177 ns)
([record](../quartus/fpu-production/README.md)). A finishing reply's 602
numeric trap selects between two forward picks, one without the finishing
slot, so it no longer passes through the pickers. The 602 worst path is the
started-flag path into a value word above.

## Arithmetic stage 1

Add, multiply, fused and `frsp` operands enter the first stage unnormalized:
a denormal keeps its raw significand with exponent −1022, so no leading-zero
count or shift precedes the multiplier or the exponent difference. The add
stage already normalizes its 112-bit sum. Its operand fields hold the full
53-bit addend and 106-bit product, so no significant bit is lost unless the
result lies below the denormal range: with k leading zeros in a product
(k ≤ 52 for one denormal factor), the sum's leading one stays at least 57
positions above the jam bit; a cancellation deep enough to matter needs an
alignment distance at most k, which shifts no addend bit past the field. Two
denormal factors put the product below 2^−2043, where only its sticky bit
survives. Single operations take binary32-representable operands, which are
normal binary64 values.

The double multiply's second cycle adds the three middle 27-bit partial
products in one ternary adder before the high product.

Remaining stage-1 work: carry the product as a carry-save pair into the add
stage, align the addend beside the multiplier, and store class tags with FPR
bits so special-operand classification leaves the first stage.

## Add and rounding stages

The add stage registers the sum's leading-zero count (0 for a carry into the
top bit, 160 only for a zero sum) beside exponent + 1, its underflow-scaled
form and `exponent − minimum + 1` clamped to 0..255. The rounding stage forms
the tiny test as an 8-bit compare and both exponent differences in parallel,
then selects; it normalizes by shifting the count and dropping the vacated low
bit, and takes count 160 as the zero test. The divider supplies count 1 or 2.

Rounding forms each result test from the unrounded mantissa beside the
incrementer: nonzero, the leading bit, the exponent at its minimum and the
biased exponent field, for both increment-carry cases, selected by the carry.
A single denormal's normalizing count follows from the sum's count and the
denormalizing shift; the rounded value keeps that count unless kept + 1 is a
power of two, whose normalized fraction is zero. Integer conversion forms its
increment, inexact and range check in the add stage, so its write suppression
is registered before rounding.

These changes keep every latency and initiation interval.

## Arithmetic units and area

`ppc_fpu_arith` instantiates one of each block so the fitter reports area per
instance: `ppc_fpu_unpack` (class bits, special results, raw operand fields),
`ppc_fpu_multiplier` (single product, and the 603e's registered 27-bit partial
products), `ppc_fpu_align_plan`, `ppc_fpu_aligner`, `ppc_fpu_adder` (sum, LZC
and the rounder's shift amounts), `ppc_fpu_convert`, `ppc_fpu_rounder` and
`ppc_fpu_divider`. The combinational steps live in `ppc_fpu_arith_pkg`.
Sharing, with every latency unchanged:

- One alignment plan serves the single path in stage 1 and the double
  multiply's second cycle; admission stops while a double multiply is in the
  input stage, so the two never meet.
- The larger-exponent operand becomes x, so only y is shifted. The adder is
  symmetric in its operands.
- `fctiw`/`fctiwz` plan a right shift of the raw significand by 31 − exponent;
  the aligned lane gives the integer part (bits 111:79), guard and sticky.
- Divide and `fres` results, including special operands, load the add-stage
  register one cycle before they are due and round in the pipeline rounder.
  The divider blocks admission, so the pipeline is empty then.

FPRs live in `ppc_fpu_fprs`: per write port one MLAB bank, copied per read
port, and a live-value table of flops selecting the bank with each register's
latest value. A register not written since reset reads zero; reads are
combinational and return the value before the cycle's writes, as the flop
array did. Each work context reads three ports: a load or store reads frS
through the first, since RA is a GPR. The inspection port shares the second
context's frC read and is valid while that context is empty, so six reads
need twelve bank copies. Each word stores its `fsel` class in a spare MLAB
bit. The 602's SP/LT tags stay in flops.

The 602 build narrows by construction: its operands are
binary32-representable, so the low 29 significand bits are constant zero into
the multiplier, add lane and divider; the aligned y lane folds bits 47:0 into
a sticky bit 48, formed from the unshifted lane and the distance beside the
shift; and the rounder shifts only the 64-bit window of bits 159:96 that single
magnitudes occupy. The fold stays below every single guard bit with
unnormalized denormal operands: a denormal x has exponent −126, so a y it
shifts is also denormal at distance zero, and a product x with one denormal
factor has at most 23 leading zeros, so a y shifted past bit 48 lies below
half of x and the result's leading one stays at least 38 bits above the
fold. A product of
two denormals lies below 2^−250, where only its nonzero sticky matters. Single
divide places its remainder sticky at bit 96 in both builds.

The 603e rounder shifts the 112-bit window of bits 159:48. Every finite
magnitude lies there: the add lane is 112 bits, a quotient occupies bits
158:104, and double divide places its remainder sticky at bit 48, below the
quotient. Fitted area per block is in
[quartus/fpu-production/README.md](../quartus/fpu-production/README.md).

The shell's own logic is now about 8.9k ALMs for the 603e and 7.9k for the
602, down from 13.0k and 10.9k; the 603e build fits in about 15.5k ALMs,
inside the ~18k budget beside the MiSTer core.

## COMPACT

`FPU_IMPL=FPU_IMPL_COMPACT` selects `ppc_fpu_compact`: the same results with
one instruction in flight and a sequenced arithmetic unit, for both
personalities. It does not meet Table 6-5; its cycle counts, design and area
are in [COMPACT FPU](FPU_COMPACT.md). The exact-cycle, stream and dual benches
run for FULL only; the numerical and architectural benches run for both.

## Memory and 602 tag SPRs

Memory packets retain complete instruction tags. Fault-free preparation does not
authorize a store: publication requires the matching commit and store acceptance.
Out-of-order load responses must reach the correct pending entry. The external
LSU owns translation, atomic transport, cache timing, and fault priority; tests
with an ideal LSU establish the FPU-side latency and initiation requirements,
not cache-system timing. The 602 target is 2:1 for single loads/stores and
`stfiwx`, and 3:2 for double loads/stores under the manual's assumptions.
[602 UM §6.8.5, Table 6-6, physical PDF 316–318]

The 602 SP/LT `mfspr` and `mtspr` operations use the same tagged issue/retirement
path. `msr_pr` permits supervisor-access checks; the GPR source/result fields carry
the raw tag word. Tag writes serialize and commit atomically. Explicit emulation
and privileged-instruction dispositions distinguish these faults from numeric
program exceptions and FP-unavailable. Inspect outputs expose committed tags.
[602 UM Table 2-6, §2.1.2.4.1, physical PDF 87, 97]

## Acceptance

Separate elaborations must pass independent raw-bit arithmetic, personality
semantics, exact execution-cycle and sustained initiation tests. Shell tests
must show rename dependency forwarding, early CR availability, delayed commit,
memory faults, cancellation, and stable backpressure. Strict lint covers both
elaborations. Fresh Quartus synthesis and timing measurements cover the changed
RTL at 50 MHz and report the 66 MHz margin separately. Prior serialized-backend
measurements are historical and do not establish this implementation's timing.
