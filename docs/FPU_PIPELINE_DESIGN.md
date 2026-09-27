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
602 arithmetic adapter widens tagged binary32 operands exactly for shared
arithmetic and stores the directly rounded binary32 result. Software-emulated
double operands never enter hardware arithmetic as invented zero-filled values.

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

The shell issue handshake represents dispatch. Operand reservation and backend
execution acceptance are distinct events; dispatch delay must not be counted as
an extra arithmetic execution stage or used to conceal excess execution latency.
The shell owns four FPR rename entries and pending instruction records. Source
bindings select the youngest older producer and retain its full identity until
the value arrives. Completion snooping updates waiting operands; rereading the
architectural bank after a stall cannot substitute for correct bindings.
[603e UM §6.3.3.1, physical PDF 258; 602 UM §§1.2.2.2, 6.4.3,
physical PDF 56, 304–305]

Pending capacity is five instructions for 603e and four for 602, selected at
elaboration. The 602 has four completion buffers and retires at most one
instruction per cycle. FPR rename capacity remains four in both builds.
[603e UM §6.3.3.1, physical PDF 258; 602 UM §§1.1.3.1.3, 6.3.2,
physical PDF 45, 299]

Finished FPR values and CR results are forwarded before architectural retirement.
The forward packet includes the full completion tag, destination, value, validity,
and 602 SP/LT tags where applicable. CR forwarding excludes `mcrfs`. Architectural
updates remain exact-tag, in-order, commit-only. A held oldest result is stable;
independent younger instructions may execute and finish while it awaits commit.
[603e UM §6.4.3, physical PDF 264]

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
