# Proposed next MMU slice: CPU-owned runtime BAT SPR access

This document preserves the design baseline for runtime BAT programming.
The implementation contract is now [RUNTIME_BAT_PROTOCOL.md](../../RUNTIME_BAT_PROTOCOL.md);
acceptance evidence is in [RUNTIME_BAT_VERIFICATION.md](../../RUNTIME_BAT_VERIFICATION.md)
and [RUNTIME_BAT_FIRMWARE.md](../../RUNTIME_BAT_FIRMWARE.md).
The existing-state descriptions below refer to the pre-implementation baseline.
The next bounded increment should let supervisor firmware read/program the
existing eight BAT pairs through MFSpr/MTSpr, retaining the live MSR context
fence. It should precede page-TLB refill, which needs additional miss state,
TGPR handling, refill instructions and data-fault delivery.

## Existing ownership and integration boundaries

`ppc_bat_service` is the single owner of committed `upper_q`/`lower_q` arrays:
four instruction pairs and four data pairs. Its request kinds include translation,
SPR read and SPR write. A successful write currently mutates storage on accepted
service request, not CPU retirement. Responses are registered and stable under
backpressure. Candidate validation rejects reserved encodings, malformed active
entries and overlapping ranges without changing the bank.

`ppc_bat_memory_router` permits those writes only before `running_q`. After start,
it multiplexes only instruction/data translations onto the service. Live context
updates carry IR/DR/PR but do not carry BAT register accesses. Its quiescence
already excludes held memory offers, in-flight routing and service responses.
`ppc_core_bat` joins that router with the core; the core decoder currently grants
no BAT SPR access. Simply allowing running writes on the existing setup port
would bypass retirement/privilege and could change mappings under an old request.

Keep `ppc_bat_service` as the sole committed owner. Do not add a second architectural
BAT bank in `ppc_special`. A private prepared candidate inside the service is
transaction state, not another visible register file. Startup programming and CPU
access must use the same banks, with startup access permanently excluded after
start. Physical/cache wrappers remain outside this composition.

## Architectural facts and bounded policies

Sources are the local *MPC603e & EC603e User's Manual* (UM) and *PowerPC
Programming Environments* (PEM); references use printed page numbers.

- UM 5-18 describes sixteen BAT SPRs in eight pairs. IBAT0U/L through IBAT3U/L
  use selectors528–535; DBAT0U/L through DBAT3U/L use536–543 (register encoding
  tables in UM chapter2). Both reads and writes are supervisor operations.
  Freeze and test the split five-bit SPR encoding and Rc/reserved fields.
- UM 5-20 says silicon does not initialize BAT registers at reset: software must
  clear all valid bits before initial configuration. It also warns against
  overlapping blocks even when translation is disabled. Existing deterministic
  zero reset remains an explicit local policy, not a silicon reset claim.
- PEM Table2-22, 2-42, requires context synchronization before and after DBAT
  writes. Table2-23, 2-43–2-44, requires context synchronization after IBAT writes
  and forbids an implicit branch across the affected instruction stream.
  The bounded implementation may conservatively serialize, drain and refetch
  every BAT write. Software must still keep the update instruction and following
  synchronization stream physically consistent; conservative fencing is not
  permission to remap the executing stream arbitrarily.
- UM 2-40 and 2-44 describes identical MFTB/MFSPR read behavior on the 603e.
  Include BAT selectors in that alias policy whenever the selected profile
  enables the full read-alias extension; aliases retain supervisor privilege.
  Do not accidentally create user BAT access or a write alias.
- Architectural SPR writes are individual half-register operations, not an atomic
  64-bit BAT-pair update. Firmware must make intermediate mappings safe. Existing
  whole-bank validation is a **local rejection policy** for bad programming,
  not an architecturally specified BAT-write exception.

## Recommended retirement transaction

The main new mechanism is a side-effect-free prepare followed by a retirement
commit. Sending today's mutating `SPR_WRITE` request before retirement is unsafe.
Retiring first and then attempting a write that can fail is also unacceptable.

1. Accept a legal supervisor BAT operation only after older completion/execution
   work drains. For a write, register a frontend fence and finish all old offered
   or accepted memory obligations under their captured old mapping/context.
   Do not block router acceptance of a previously held request to obtain idle.
2. At explicit frontend/router quiescence, send a **prepare write** request with
   selector and value. The service validates the candidate against its current
   committed banks, stores a private proposal, and reserves the write slot.
   It returns success or a no-mutation rejection. The successful proposal is not
   visible to translations or SPR reads. No other owner can mutate the banks.
3. Publish the CPU instruction result only after a successful prepare, or publish
   the existing diagnostic result for a locally rejected candidate. Hold the
   fence through result/retirement backpressure. A rejected candidate must not
   become an invented DSI/program exception or a successful silent no-op.
4. On the accepted CPU retirement edge, pulse **commit prepared write**. Because
   the service reserved the slot, commitment cannot stall or reject; the sole
   bank changes on that same edge, exactly once. Assert a matching successful
   reservation. Preserve a registered acknowledgment, then refetch the operation's
   retained resume target while the frontend is still fenced; release only after
   accepted redirect. The initial target is PC+4. Any accepted recovery that
   retains this BAT instruction replaces that target, and the latest such target
   survives commit and acknowledgment. An unconditional PC+4 redirect must not
   overwrite it.
5. Before the CQ offers this instruction as its finished retirement head, an
   accepted recovery killing its exact identity aborts the proposal. A coincident
   kill and execution-result acceptance must follow existing exact-tag recovery
   precedence; result publication alone does not block recovery. If a request/
   response is already offered, keep the transport obligation stable and drain
   it; consume any response and release the reservation before reuse. A
   retained-identity cut retains its proposal. Since this operation enters an
   empty CQ and is serialized, accepted completion normally makes it the offered
   retirement head on the next cycle. The existing CQ rule protects that offered
   head, including under retirement backpressure. After accepted retirement the
   write/ack/refetch sequence is irrevocable.

This is analogous to the committed context fence but updates the canonical bank
at retirement, rather than asking a fallible service to mutate it afterward.
This proposed BAT target policy deliberately differs from the existing MTMSR
retained-recovery/refetch policy: `tb_core_live_context` phase5 expects MTMSR to
refetch PC+4. That established behavior is not a current RTL defect and is not
changed by this proposal. The BAT contract needs its own retained-target register
and independent acceptance test, rather than assuming every context operation
already implements this policy.

Same-edge preparation and cancellation must be explicit:

- If an offered prepare handshakes on the same edge as an accepted exact-identity
  kill, complete the handshake, suppress any CPU result, and abort/drain the
  resulting proposal and response. Service update ordering must make abort win
  over retaining a newly accepted reservation on that edge; no bank mutation is
  possible because prepare itself is side-effect free. If abort delivery occurs
  on the following edge, keep the cancelled transaction exclusively owned until
  that abort and response drain finish.
- A prepare already offered but not yet accepted cannot be withdrawn or have its
  selector/data changed on a kill. Latch cancellation, hold the request stable
  until handshake, then abort/drain it. Do not release the fence or reuse its
  transaction slot merely because its CQ owner was killed.
- A recovery retaining the BAT identity does not abort or drain away its proposal;
  it records the accepted recovery target for the final refetch. A later accepted
  retained recovery replaces that target. A killing recovery instead follows the
  normal cancelled-transaction drain and its accepted redirect.
- Reset cancels offered/in-flight requests under the transport reset contract,
  clears every private reservation, cancellation latch, retained target and
  response/commit acknowledgment, and applies the existing committed-bank reset
  policy. No pre-reset response or acknowledgment may complete a post-reset
  operation.

A commit and abort must never coincide. Requests may not reuse a reserved slot
until all prior responses and cancellation obligations are gone. A single
outstanding transaction can avoid public IDs; if concurrency is added later,
introduce an explicit identity/generation token before relaxing that invariant.

Reads need no bank mutation. A conservative first implementation can use the same
fence/drain and capture a read response before offering its GPR result, then
refetch the retained resume target on retirement (initially PC+4, updated by any
accepted recovery retaining that read). This adds latency but makes service arbitration and
cancellation simple. A future optimization may allow read arbitration alongside
fetch only with a stable sampled response and unchanged write exclusivity.

## Proposed interfaces to freeze

Suggested feature parameter: `ENABLE_RUNTIME_BAT=0`, requiring live context and
supervisor exceptions. IRQ and timers need not be required, but their enabled
combinations must preserve pending events while a BAT write is in flight.

Core/special to router/service:

- `bat_csr_req_valid_o/ready_i`, `bat_csr_req_write_o`,
  `bat_csr_req_spr_o[9:0]`, `bat_csr_req_data_o[31:0]`.
  Write requests mean prepare only; reads capture the committed value.
- `bat_csr_rsp_valid_i/ready_o`, `bat_csr_rsp_data_i[31:0]`, plus explicit
  rejected/unsupported/config/overlap/invalid-entry status for diagnostics.
- `bat_csr_commit_o`: retirement-edge pulse for the reserved successful write.
  Its receiver is guaranteed ready by reservation; no combinational ready/retire
  loop. `bat_csr_abort_o` releases a precommit proposal while outstanding response
  drain remains separately observable. Registered completion/idle status must
  let the core distinguish response drain, reservation release and commit ack.

The router multiplexes these requests with startup and translation activity but
never blocks old memory progress merely because a new CSR prepare is waiting.
After fence drain, the reservation exclusively owns the service until commit or
abort. Existing MSR context installation must not interleave with a prepared BAT
write. Define router **memory-drained** independently from **CSR-transaction-idle**:
a core waiting for its own prepare response must not wait for a quiescence bit
that requires the prepare to disappear. Existing quiescence semantics may need a
separate CSR-idle output rather than changing the meaning of old profiles.

Exact pin names, response acknowledgment and reservation lifetime need agreement
between core and service owners before implementation. Also freeze whether
`ENABLE_RUNTIME_BAT` itself enables the existing full MFTB/MFSPR alias extension
(currently associated with the timer profile); recommended behavior is identical
read aliases for all implemented selectors in either opt-in extension, while
all old default-profile decoding remains unchanged.

## Invalid entries, intermediate states and remaining faults

Retain current service policy initially: reserved bits and malformed BL encodings
reject even for an inactive entry; active-entry alignment and whole-bank overlap
are checked before activation. Disabling Vs/Vp removes an entry from translation
and overlap checks. Firmware can invalidate the upper half, write a new lower
half, then install a valid upper half. Do not reject that legal inactive staging
sequence merely because its intermediate BEPI/BRPN do not form an active mapping.
Do not temporarily expose the prepared bank to translation during validation.

Keep selector/value readback exact for accepted writes. Rejected writes preserve
both halves and every other entry. The diagnostic outcome must be visible before
retirement is offered, with no partial bank update. Explicit tests must distinguish
inactive staging, activation rejection and fully valid remapping.

A runtime BAT writer does not add a page MMU. Existing instruction protection/
guarded causes can enter typed ISI handling; misses, malformed configuration and
unrepresentable combined causes keep current terminal policy. Data translation
failures still produce the bounded diagnostic path, not precise resumable DSI.
Physical bus errors remain separate terminal transport events. Consequently the
first compiled acceptance workload must avoid data-protection faults; negative
coverage should confirm their existing diagnostic behavior without claiming DSI.
No cache/TLB coherency or decoded cache maintenance is implied.

## Acceptance gates and ownership

1. **Freeze protocol:** core/special owner and BAT service/router owner agree
   prepare/commit/abort, sampled read semantics, quiescence, exact rejection and
   alias/privilege rules. Independent verifier reviews all collision boundaries.
2. **Service gate:** prove no mutation before commit; one mutation at commit;
   stable responses; rejection and abort preserve committed state; default
   startup behavior unchanged. Cover inactive pair staging, overlap in both
   privilege domains, malformed BL/reserved fields and arbitrary response stalls.
3. **Core gate:** directed architectural tests cover all sixteen selectors,
   readback, problem-state access, aliases, preceding delayed stores/loads, held
   old fetch offers/responses, retirement stalls, exact killed/retained recovery,
   and IRQ/DEC pending across prepare/commit/refetch. Include an accepted recovery
   retaining an unfinished BAT operation with target0x200; after commit/ack,
   require refetch at0x200 rather than the BAT instruction's PC+4. Exercise kill
   coincident with prepare acceptance, kill while prepare ready is low, and reset
   in every reservation/response/ack phase. No request may cross bank
   installation using a mixed old/new mapping.
4. **Compiled gate:** start in real mode with no harness BAT programming. Firmware
   clears valid bits, installs identity instruction/stack mappings and a data
   alias, reads every programmed half back, enables IR/DR, accesses the alias,
   disables/invalidate-reprograms a data BAT, and proves the alias moves to a
   second physical location without modifying the first. Keep update code and
   stack continuously reachable. Include handler entry/RFI and a pending IRQ/DEC
   at a write boundary, plus a corrupted readback expectation negative run.
5. **System gate:** strict default/enabled lint, independent old/new regression,
   compiled evidence, frozen source manifests and fresh integrated timing. Only
   then describe CPU-programmable BAT as complete; page-TLB refill remains next.

Suggested ownership: one agent owns the canonical BAT service plus router
reservation/arbitration; one owns core/special/decode and wrappers' CPU CSR API;
one independent verifier owns benches/Makefile; root owns BAT wrapper composition,
compiled firmware and acceptance evidence. Avoid concurrent edits to the service
bank update block or core special-state machine. Keep the current timer/IRQ RTL
freeze intact while reviewing this proposal.
