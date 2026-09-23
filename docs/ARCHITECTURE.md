# Scaffold architecture

Current cross-system percentages, gaps and validation boundaries are tracked in
[SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md). Historical milestones below retain
their original scope and dates; later feature contracts supersede early limitations.
The current opt-in data-protection path is described in
[DATA_EXCEPTIONS.md](DATA_EXCEPTIONS.md): BAT PP denials can be handled and
retried, while page misses and physical transport errors remain separate.


The opt-in page-hit profile now routes clean BAT misses through the canonical
CPU-managed segment bank and the I/D TLB service. It captures access context,
uses PA/WIMG only on allowed hits and keeps page failures diagnostic. The TLB
control port is external preload/management, not CPU software refill. See
[PAGE_PATH_PROTOCOL.md](PAGE_PATH_PROTOCOL.md) and
[PAGE_FIRMWARE.md](PAGE_FIRMWARE.md). Earlier standalone-service descriptions
below are historical; automatic miss state, TGPR, handler refill/retry, combined
cache/bus integration and timing acceptance remain open.

The separate opt-in CPU TLBIE path now prepares indexed invalidation and commits
it at retirement, then acknowledges and refetches. Both ways in both banks are
invalidated; external TLB loading remains a test/control operation. See
[CPU_TLBIE.md](CPU_TLBIE.md) and [TLBIE_FIRMWARE.md](TLBIE_FIRMWARE.md).

`ENABLE_TLB_LOAD` adds committed DCMP/ICMP/RPA seed registers and privileged
real-mode `tlbld`/`tlbli`. The CPU captures the selected compare word, RPA,
SRR1.WAY and old RB, validates the bounded input contract, and commits a private
refill proposal through the same sole TLB service. Compiled software can install
and use I/D page mappings without external preloads. This is CPU-seeded loading;
automatic miss capture, TGPR and software page-table search/retry remain open.
See [CPU_TLB_LOAD.md](CPU_TLB_LOAD.md), [TLB_LOAD_PROTOCOL.md](TLB_LOAD_PROTOCOL.md)
and [TLB_LOAD_FIRMWARE.md](TLB_LOAD_FIRMWARE.md).


Status: executable integer/control/memory bootstrap, 2026-09-14. The desired final architecture remains the 603e-style machine in the original implementation plan. Statements in that plan about variants, endian transformations, latency, bus qualification, resource estimates, and manual completeness are design inputs to verify, not conformance established by this scaffold.

## Current datapath

```text
instruction request/response
        |
  ppc_fetch (one outstanding request, redirect/drain PC)
        |
  ppc_fifo (six-entry IQ)
        |
  ppc_decode --> architectural GPRs + latest-writer rename lookup
        |                           |
        |
  atomic CQ + rename allocation and IU station capture
        |
  ppc_dispatch (one IU reservation entry, tagged operand wakeup)
        |
  ppc_iu (registered issue, held tagged result)
        |
  ppc_completion (five entries, ownership-checked finish)
        |                  |
        |             rename values / operand wakeup
        |
  finished head retirement writes GPR and releases rename slot
```

One instruction dispatches per cycle. Dispatch allocates an unfinished completion entry and pending rename destination; a reservation station waits for source values and issues to a registered IU. Completion accepts results by slot and generation and retires only the finished head. The single IU issues in order; direct CQ tests exercise younger finishes before older ones in preparation for additional units. Explicit recovery control restores a surviving instruction prefix and drains old fetch traffic; a serialized branch lane now supplies architectural control flow. Fetch transport usually limits throughput below one instruction per cycle. These stage choices do not establish processor timing conformance; see [EXECUTION_CONTRACT.md](EXECUTION_CONTRACT.md).

## Ownership and invariants

| Module | Owns | Contract |
|---|---|---|
| `ppc_pkg` | Packet layouts and fixed queue/tag sizes | Host bit slicing uses `[31:0]`; PowerPC manual bit numbers must be translated explicitly in future work. |
| `ppc_fetch` | Next PC and outstanding response state | Advance sequentially after accepted normal responses; preserve old offers and drain/discard old responses before installing the latest accepted redirect target. |
| `ppc_fifo` | Circular storage and occupancy | Ordered, no fall-through; accepted redirect clears with priority over push/pop; simultaneous normal push/pop preserves count; a full queue advertises capacity the cycle after a pop. The IQ has depth 6; CQ owns its separate depth-5 ring. |
| `ppc_decode` | Supported opcode classification | Reject unknown opcodes and unsupported OE/Rc forms; rA=0 literal-zero behavior only for add immediate forms. |
| `ppc_dispatch` | One IU reservation entry and pending operands | Source wake requires rename slot and completion identity; ready issue remains stable under backpressure unless an accepted identity-matched recovery cancels it. |
| `ppc_flags` | Committed CR/XER and exact-tag owner control | Record-logical ownership and CR0 commitment connected; ADD/ADDC/ADDE/ADDME/ADDZE update CA/OV/SO; [ADDME/ADDZE](ADD_UNARY.md) now implement captured-carry decrement/increment. |
| `ppc_special` | Serialized branch/LR/CTR/compare and scalar data transactions | Drains older work, blocks younger dispatch, uses ordinary tagged completion; no BPU/LSU timing acceptance. |
| `ppc_iu` | Registered ADD family, eight Boolean operations rotate/mask and logical shifts with held result | One atomic GPR/CR0/XER result per issue; no variable latency or exception generation. |
| `ppc_regfile_gpr` | Committed GPR state | Only retirement writes; update loads atomically write their data and base through two ports. r0 is an ordinary writable register. Zeroing on reset is a deterministic test convenience. |
| `ppc_rename` | Five values, valid/ready bits, producer identities and latest-writer map | Each dispatched writer gets a free slot; reads see the newest unretired writer or wait for its accepted finish; retire clears the map only if it still points at that retiring tag; simultaneous younger allocation wins. |
| `ppc_completion` | Ordered allocations with independent finish state | Reject invalid/stale/duplicate finishes; only finished head retires; output remains stable while stalled; accepted prefix cuts preserve that irrevocable head and suppress killed finishes. |
| `ppc_core` | Resource gating, commit, stop/halt state | IQ pop, rename/CQ allocation and reservation capture are atomic; only accepted redirects clear frontend state and cancel exact producer identities; unsupported instructions allocate a CQ entry without a GPR rename slot. |

No rename slot is reclaimed for allocation in the same cycle as release. This intentionally creates a bubble at capacity. Result data appears in both rename storage (operand lookup) and completion packets (retirement trace/writeback); a future completion redesign may replace this duplication with result-tag reads.

## External interface

All signals use one clock. `rst_ni` is an active-low **synchronous** state reset and also masks valid/ready outputs combinationally. The environment must present reset on a clock edge and cancel old memory transactions on reset. There is no reset synchronizer or separate bus clock.

Instruction transport uses byte addresses and normalized 32-bit instruction words; it does not model byte lanes, memory faults, endianness, cache lines, or a physical bus. Acceptance occurs at a rising edge where valid and ready are both high. The responder must retain data until accepted. A response may be asserted immediately, but the core will accept it only after registering the request; a pulse-only same-cycle responder is unsupported. At most one response may be outstanding. `req_addr` is meaningful while request valid is high.

`retire_valid_o` and `retire_o` describe the oldest finished packet. `retire_ready_i` controls **architectural commitment**, not just trace collection. Tie it high for ordinary execution. For stores, ready also authorizes a latched reservation at the serialized head before the external request; that request becomes irrevocable, and final retirement acknowledges its completion. See [CONTROL_MEMORY.md](CONTROL_MEMORY.md) for this extension of the ready contract. On acceptance of a legal packet, its GPR value commits. The tag field is internal bookkeeping, not architectural state.

At dispatch of an unsupported instruction, fetch stops (an already offered request can still complete) and younger IQ entries remain inert. Older instructions drain. The unsupported packet retires with `illegal=1` and `gpr_write=0`, then `halted_o` remains asserted until reset. It is a diagnostic event, not a PowerPC exception vector. An exact younger diagnostic can be killed before commitment through [explicit recovery control](CORE_RECOVERY.md); committed halt remains terminal. Interrupt and architectural exception vectoring remain absent. Alignment and abstract data-response errors now produce ordered diagnostics through the serialized memory lane.

## Replacement boundaries

1. Extend the current local-producer recovery contract before adding external or variable-latency producers. Define additional reservation stations and CR/XER/FPR destination classes with their own accepted contracts.
2. Widen IQ read/insert, operand ports, allocator, completion admission, and commit to two lanes together; apply documented unit and destination-class restrictions. Do not merely remove the `DISPATCH_WIDTH` guard.
3. Insert IMMU/I-cache below fetch and DMMU/D-cache below the LSU, retaining a simple uncached transport during bring-up. The final 60x wrapper needs explicit output enables and independent address/data tenure machinery; the current transport must never be labeled 60x-compatible.
4. Replace diagnostic halt with precise exception entry and refetch. Extend retirement records for CR/XER/FPR/SPR and memory effects so architectural comparison remains possible.

Future CPU variants must be backed by explicit capability records and tests; no unverified PVR or cache/TLB/FPU variant settings are exposed today. Historical pre-tagged-bootstrap Quartus results and the measurement-wrapper assumptions are recorded in BUILD_STATUS.md; they do not establish final CPU area or timing.

## Tool-compatibility update

P04 moved FIFO derived local parameters into the module body and replaced named struct assignment patterns with explicit field assignments in fetch/core for Quartus Lite 17.0.2. These syntax-only changes preserve one canonical RTL source set for simulation and synthesis. Strict lint and the original 768-result regression passed after the change.

The decoder now includes 168 forms, including RLWINM/RLWNM, record-logical and ADD/ADDC/ADDE/ADDME/ADDZE OE/Rc forms with captured SO and masked flag commitment; see [RECORD_LOGICAL.md](RECORD_LOGICAL.md) for execution validation. The separate seven-form stage probe remains a bounded timing regression.

[ADD/ADDC flag execution](ADD_FLAGS.md) adds CA, OV and sticky SO through the existing atomic owner/commit path. [ADDE](ADDE.md) captures committed CA; [ADDME/ADDZE](ADD_UNARY.md) are implemented in a separate slice.

[RLWINM/RLWNM](ROTATE_EXECUTION.md) capture a decoded 32-bit mask in the reservation station and issue packet. The IU rotates the source left by operand B’s low five bits, then masks the result. Immediate SH bypasses register lookup; register counts retain their ordinary tagged dependency. Record forms capture SO and commit CR0; XER permissions stay clear. RLWIMI still requires an old-destination dependency and remains unsupported.

## Serialized companion lane

The diagram above describes the ordinary IU path. [CONTROL_MEMORY.md](CONTROL_MEMORY.md) specifies the serialized companion: special instructions enter only after older CQ/IU work drains, retain a completion identity, and block younger dispatch through retirement or memory-response drain. A third committed GPR read supplies store data. Nongpr-writing operations use CQ entries without GPR rename allocation. BF-selected comparison masks extend CR0-only packet handling; LR/CTR updates remain inside the companion until matching commitment.

The new data interface is an uncached aligned-word transport with big-endian byte enables and one response per load/store request. It does not expose physical bus pins or translation. A committing taken branch wins over an external redirect, whose acceptance output stays false on that edge. A cancelled load keeps any held offer and drains its reply. Stores require a latched retirement authorization before making an irrevocable offer.

A faulted load suppresses GPR write/wake and enters terminal diagnostic halt; its rename allocation remains until reset. Resumable exceptions must explicitly reclaim that ownership. No new Quartus fit or timing measurement accompanies this lane.

[SLW/SRW](LOGICAL_SHIFTS.md) use the existing two-operand registered IU path, consume low-six-bit counts and preserve XER. No interfaces change. SRAW/SRAWI now share ALU_SRAW in an explicitly widened five-bit enum; they replace CA from discarded negative-source bits and preserve OV/SO.

RLWIMI uses the two existing rename read ports for rS and old rA. The five-bit SH is a separate captured field in uop/issue packets and the reservation station; its destination allocation does not replace the source mapping before capture. The IU merges masked rotated rS with unmasked old rA, then derives CR0 from that merged result for Rc. No third rename read port or serialized execution is required.

SUBF/NEG share ALU_SUBF and the existing adder with complemented A plus carry-in one; NEG supplies immediate zero B. Both preserve CA, while OE/Rc use the existing owner-controlled OV/SO/CR0 path.

SUBFC extends the complemented-A arithmetic path with an always-enabled CA write; the carry-in is fixed one, independently of committed CA. Its result carry expresses unsigned no-borrow.

SUBFE adds a complemented-A operation with captured carry-in, sharing the flag owner and registered arithmetic path. Its overflow calculation includes the borrow adjustment.

SUBFME/SUBFZE reuse ALU_SUBFE with immediate B=ffffffff/0, reserved rB=0 and real rA. Both capture and replace CA without a register dependency on the encoded reserved field.

SUBFIC uses ALU_SUBFC with signed SIMM and real rA0, replacing only CA alongside its GPR result. All low16 bits are data; no OE/Rc decoding applies.

ADDIC/ADDIC. use ALU_ADDC with signed SIMM and real rA0. Both replace CA; only primary13 captures SO and records CR0. Immediate low bits never select OE/Rc behavior.

ANDI./ANDIS. read real rS and write rA through ALU_AND using an unsigned low/high-half immediate. Both record CR0 with captured SO, preserving all XER bits.

CNTLZW/EXTSB/EXTSH use three integer ALU operations with a captured rS operand and constant-zero B. Exact ten-bit XO matching and zero reserved RB are required. Rc forms capture SO and update CR0; non-record forms allocate no flag owner. XER is preserved. CNTLZW returns 0–32; EXTSB/EXTSH sign-extend the low byte/halfword.

MFCR/MTCRF execute through the serialized special lane after older work drains. MFCR captures full CR at dispatch and returns it as a GPR value. MTCRF captures rS, carries its FXM in allocation-owned `write_cr_fields`/`cr_mask` metadata, and returns the source in `result.value`. Completion constructs a masked CR delta; flags independently applies the allocated mask at retirement. Neither changes XER.

The eight CR Boolean operations use SPECIAL_CR_LOGIC and snapshot both source bits from committed CR. Allocation-owned `write_cr_bit`/`cr_bit` selects one architectural CR bit. Completion uses only `result.value[0]` to form that bit delta; flags applies the same single-bit mask at retirement. CR fields, remaining CR bits, GPRs and XER retain their existing ownership and preservation rules.

## Update-addressing memory and bus integration

[LSU_UPDATE.md](LSU_UPDATE.md) adds 14 aligned D/indexed update forms. The completion allocation owns `update_write` and `update_gpr`; an accepted successful memory result supplies `update_value`. On retirement the regfile writes loaded data and updated base together. Faults clear both permissions. The serialized special lane drains older work and blocks younger dispatch through retirement, so the base update needs no second speculative rename allocation. This restriction must be revisited before pipelining the LSU. Store aliases use captured pre-instruction state.

[BUS_MASTER.md](BUS_MASTER.md) defines the separate `ppc_bus60x` data adapter. It uses explicit output enables and independent address/data grants, with one outstanding transaction and address-retry qualification before starting data. The current core supplies scalar byte masks on reads as well as stores. Core integration tests connect this module to the normal data transport and compare every retirement against independent byte-memory expectations. The bus block adds falling-edge busy-release registers; these require later FPGA timing review. The unified wrapper below extends this adapter to instruction fetch. The full processor pinout and remaining bus modes remain open.

[REFERENCE_RUNNER.md](REFERENCE_RUNNER.md) records actual original-handler DingusPPC comparisons. The reference provides architectural state evidence for its accepted subset, with adapter-owned legality/dispatch and explicit unsupported operations. It provides no cycle, cache, MMU or exception-conformance evidence.

## Unified transport and divider reservation

[BUS_INTEGRATION.md](BUS_INTEGRATION.md) describes `ppc_core_bus60x`: a reusable core, captured-owner instruction/data router and scalar bus adapter. Instruction fetch and data accesses share one outstanding bus transaction, with round-robin contention handling and TC=10/00 attributes. Failed instruction reads cause a reset-only transport diagnostic, not an architectural instruction exception; older queued instructions may still retire. Full instruction-fault delivery remains open.

[DIVIDER_TIMING.md](DIVIDER_TIMING.md) extends the IU with a bounded execute reservation. With accepted issue at E, earliest accepted divide finish is E+20 by default or E+37 for the PID6 configuration. Ordinary arithmetic and logical IU operations retain the single-cycle interval; multiply reservations are described below. Recovery cancels held work by its completion identity even before result-valid, and a finished result remains stable under backpressure. The new `ppc_divider` performs 16 radix-4 magnitude iterations, restores signed quotient polarity and holds the result until release. The single IU serializes competing operations; accepted finish still follows the configured 20/37-cycle interval. Latencies below 17 cannot accommodate the engine and are rejected.

## Burst refill and full-RAM reference

[BUS_LINE_READ.md](BUS_LINE_READ.md) defines the separate `ppc_bus60x_line_read` building block. It reads four 64-bit physical beats starting at any of the four critical doublewords, confirms each provisional beat through DRTRY, and returns a complete 256-bit line in base-address order. TEA returns an error without publishing a partial line. It has its own file list and tests; the standalone cache controller below consumes this interface. Integration with the actual core bus arbiter remains open.

The v2 [reference lane](REFERENCE_RUNNER.md) executes original DingusPPC load/store handlers using an explicit aligned big-endian flat RAM service. Its 102-field trace adds all 64 RAM words to the 38 register fields. It covers all 168 implemented forms with full-state comparison; the immutable instruction image remains separate from data RAM, and MMU, self-modifying code, architectural fault delivery and cycle conformance are outside this oracle.

## Conservative multiply scheduling and standalone instruction cache

The IU distinguishes internal `ALU_MULLI` from `ALU_MULLW` while retaining the same architectural encodings and captured operands. It reserves MULLI for 3 cycles, MULLW/MULHW for 5 and MULHWU for 6, using the maximum latency in each Table 6-4 row. This is an explicit conservative scheduling profile. The manual table does not identify the operand-to-cycle mapping, so the shorter listed latencies and their conditions remain unresolved. Result validity controls dependency wakeup; cancellation can replace a held operation without stale writeback. The product datapath remains combinational.

`ppc_icache` stores 128 sets of four 32-byte lines, with physical tags and exact four-way LRU ranks. It accepts one aligned 32-bit instruction request at a time and returns a held response. A miss requests a critical-doubleword-first burst but waits for the entire confirmed line before installing and responding. Kill retracts an unaccepted refill or drains an accepted one without installation. Invalidate clears validity and similarly discards outstanding fetch work; kill/invalidate suppress a same-edge fetch response handshake. Data storage is not reset. The controller exposes local controls, not architectural HID0 operations, and its reset models hard reset.

The independent cache/burst bench connects this controller to `ppc_bus60x_line_read` and checks instruction results through a physical pin responder. The original `ppc_core_bus60x` wrapper uses scalar fetch; the new cached wrapper below routes actual CPU fetch through the cache. Translation, permissions, cache lock, software cache instructions, early forwarding, hit-under-refill, and M10K inference/FPGA timing acceptance remain open.

Seeded reference stress reuses one pair of compiled reference and RTL executables across deterministic mixed programs. Each seed records its generated instructions, dynamic coverage, full register/RAM traces, input hashes and a reproduction command. This extends the fixed corpus with varied dependencies, memory aliases and bounded control flow; it does not replace the fixed all-168-form coverage gate or provide a processor timing oracle.

## Cached CPU and translation/exception foundations

`ppc_core_cached_bus60x` combines the default-profile core, instruction cache, line-read master and scalar data master. `ppc_bus60x_master_select` selects one physical owner fairly on simultaneous requests, retaining ownership until its response is consumed and all its output enables are released. Only the owner sees termination/grant inputs. The core fetch unit owns redirect discard: the cache completes an accepted old-path request so fetch can drain it. A fetch transport error suppresses the instruction and sets a reset-only diagnostic. Architectural exception delivery and cache enable/invalidate instructions are not part of this wrapper.

`ppc_bat_translate` is a stateless selected-bank translator: the caller provides four IBAT or DBAT pairs and explicit access/MSR inputs. It returns real-mode bypass, a unique BAT translation with WIMG/PP, a protection/guarded failure, or a BAT miss for a future segment/TLB path. Unsupported encodings, misaligned bases and overlapping active mappings have a documented local configuration-error outcome. The module does not provide BAT register storage or invoke exceptions.

`ppc_exception_state` accepts one already-selected committed-boundary event and updates MSR/SRR0/SRR1 on acceptance, holding the corresponding result under backpressure. Supported events are SC, illegal/privileged program exceptions and bounded RFI; a separate atomic state-load port is an integration/test interface, not an implemented CSR instruction. Pending-event priority, oldest-fault selection, CPU cancellation, CSR decode and architectural reset remain outside this module. Reserved-state handling follows the explicitly documented source interpretation and is not a CSR readback-conformance claim.

The cached original-handler reference compares the full architectural trace and bounded RAM through independent bus pins. Round 37 added this wrapper without modifying core RTL. Round 38 adds the opt-in supervisor path below and repeats default-profile regression.

## Round 38 integration boundaries

The plain `ppc_core` now has an opt-in `ENABLE_SUPERVISOR_EXCEPTIONS` parameter. Selected supervisor instructions use the serialized special lane; MSR/SRR state changes only at its accepted completion boundary. A committed exception holds the lane busy and excludes external cuts until the internal redirect clears the younger fetch/queue path. The existing untagged fetch response obligation is drained across that redirect. Privileged CSR forms have their allocation permissions removed before they can reserve or write architectural destinations. MFMSR masks reserved bits on read. Unsupported return modes produce a diagnostic without installing a context the CPU cannot execute. The local retirement packet still needs a future explicit architectural exception-event representation; see [supervisor integration](SUPERVISOR_INTEGRATION.md).

`ppc_bat_service` owns separate four-pair IBAT and DBAT banks behind one accepted-request/held-response interface. SPR requests and translations serialize against the same committed banks; a stalled result cannot change when a subsequent write is offered. Candidate writes validate the selected bank before committing one half. This is a bounded local service, not decoded BAT instructions, silicon BAT reset behavior or an architectural replacement for the segment/TLB path.

`ppc_core_cached_bus60x_managed` adds a maintenance interface around the original cache. It blocks new fetch acceptance, drains accepted responses, performs requested invalidation, switches mode and holds completion. Mode changes force invalidation. Disabled fetch shares the scalar bus adapter with data traffic and issues real single-beat instruction transactions. Maintenance does not empty the CPU pipeline: the changed-code test uses a separate accepted external restart while completion is held. No decoded HID0/icbi/isync or automatic context-synchronization claim follows from this local handshake.

## Round 39 integration boundaries

Exact opt-in ISYNC/SYNC/EIEIO use the existing serialized special lane. SYNC/EIEIO have no architectural destination and complete only after older CPU memory responses and retirement. ISYNC redirects at its accepted commit to PC+4 using keep-pivot recovery; queued/prefetched old instructions are discarded and accepted fetch obligations drain. This does not perform cache maintenance or establish global coherent ordering.

`ppc_core_bat` combines the default-profile CPU with `ppc_bat_memory_router` and the BAT service. Setup writes occur while the CPU is held reset; accepted start fixes local IR/DR/PR until reset. One captured I/D owner runs translation, physical request, and held response in order. The router preserves physical response obligations across CPU redirects. Translation denial suppresses physical access: instruction denial is a reset-only transport halt and data denial returns the current diagnostic error path. The physical ports expose WIMG metadata without a downstream cache/bus interpretation. No supervisor opt-in parameter is exposed because live MSR changes are not connected to this fixed translation context.

`ppc_tlb_service` owns separate instruction/data banks of 32 sets and two ways. A software-managed refill supplies normalized VSID/page/RPN/PP/WIMG/C and a selected way; valid entries imply referenced state. A permitted store with C=0 requests software changed-bit work and returns no PA. Indexed invalidation clears both ways in both banks without tag comparison. Local reset clears validity and duplicate refills into the other way are rejected. Segment registers, replacement selection, page-table accesses, miss exception state and CPU routing remain separate work.

## Incremental SPRG integration

The enabled supervisor decoder accepts SPR272–275 through the existing MFSPR/MTSPR operations. `ppc_special` owns four 32-bit scratch registers, uses the captured selector and source value, and changes only the selected register at the matching accepted retirement in `S_HOLD`. Reads use normal tagged GPR completion. The core normalizes problem-state access into the existing privilege event before allocation, removing the original register permissions. This requires no new ports, package operations or file-list dependencies. Hard reset clears all four SPRGs to the documented zero value; no separate soft-reset path is modeled. [SPRG_INTEGRATION.md](SPRG_INTEGRATION.md) records exact encodings and acceptance.

## Standalone segment-register storage

`ppc_segment_registers` holds sixteen normalized descriptors behind one response slot. Accepted supervisor writes change one entry at the accepting edge; reads and internal snapshots capture the selected descriptor, index and address. A held response blocks later writes, while response consumption may accept one following request on the same edge. T=0 reserves HDL bits 27:24 and normalizes them to zero; T=1 is retained as an opaque word. The response makes no translation or access-permission decision, and future consumers must separately retain request PR/access metadata. Reset-to-zero is a local service policy; silicon SR contents are unknown after hard reset. This module has a separate file list and is not in the canonical CPU/TLB path.

## Translated physical instruction-cache composition

`ppc_core_bat_cached_bus60x` composes CPU-owned BAT/page translation with the
managed physical I-cache and scalar/line 60x masters. Permission precedes
lookup; only WIMG=0000 is cache eligible. Data remains uncached. External
maintenance drains instruction obligations before invalidating and holds new
fetches until its completion is acknowledged. It does not implement `icbi`,
a store barrier or automatic CPU prefetch synchronization.
See [the integration contract](TRANSLATED_ICACHE.md).

The fetch unit admits a new request only when the sole downstream instruction
queue has space, retaining any held offer. With one outstanding request and
no other queue producer, this reserves response capacity and prevents a held
instruction response from blocking a data transaction behind the shared
translation router.
