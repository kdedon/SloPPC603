# Bounded instruction-cache storage and refill controller

`rtl/ppc_icache.sv` is a standalone, physically addressed instruction-cache
controller between a one-word fetch channel and the abstract 256-bit response
channel of `ppc_bus60x_line_read`.  It implements storage, lookup, exact LRU
replacement, complete-line refill, invalidation, and killed-refill draining.
The cached core wrappers connect this controller to `ppc_core` and the 60x
line-read transport; this document describes the standalone controller contract.

## Primary-source contract

The source is the local *MPC603e & EC603e RISC Microprocessors User's Manual*,
MPC603EUM/AD, 11/97.  The cache organization and Figure 3-1 were checked in the
rendered manual at PDF 129 / printed 3-3.  Section 3.1.2 and the control prose
were checked at PDF 130 / printed 3-4.  The hard-reset state is Table 4-8 at
PDF 177 / printed 4-19.  The Chapter 8 overview was checked at PDF 310–312 /
printed 8-2–8-4.

Section 3.1.1 defines a 16-Kbyte, four-way instruction cache with 128 sets and
eight 32-bit words per 32-byte block.  In conventional HDL numbering, physical
address bits `[31:12]` are the 20-bit tag, `[11:5]` select the set, `[4:2]`
select one of eight words, and `[1:0]` must be zero.  These correspond to the
manual's PA0–PA19, A20–A26, and A27–A31 notation.  Lines cannot cross their
32-byte boundary.

The manual calls instruction replacement strictly LRU: the least-recently
used block is filled on a miss.  The controller stores a unique rank for each
of the four ways in every set.  Rank zero is most recently used and rank three
is least recently used.  A hit or successful refill moves that way to rank
zero and ages exactly the ways that were newer.  An invalid way is selected
before any valid way; the lowest invalid way supplies deterministic reset
behavior.  Once all ways are valid, only rank three is replaced.

The generic Chapter 8 replacement paragraph at PDF 312 says “both lines” in
a set are valid before selecting LRU, which conflicts with the four-way
geometry stated repeatedly in §§3.1.1 and 8.1.1 and shown in Figure 3-1.  This
controller does not reduce the cache to two ways or invent pairwise behavior;
it applies the instruction-cache section's explicit strict LRU rule to all
four ways and retains the wording conflict here.

Table 4-8 says hard reset invalidates all blocks, zeros the tag directory, and
initializes distinct LRU values.  `rst_ni` represents hard reset, but clears
only validity.  Software cannot read the tag directory, and an invalid block
never hits, so tag contents are unobservable until a refill writes them; the
tag RAMs are not cleared.  The LRU RAM is not cleared either.  Instead the
first install into an all-invalid set writes the ranks that distinct reset
ranks {0,1,2,3} (way 0 most recent) would reach after touching the victim.
Reset and flash invalidation leave every set all-invalid, and ranks select a
victim only once all four ways are valid, so replacement order is identical to
a zeroed directory with distinct reset ranks.  No walk-clear or post-reset
busy period is needed.

## Storage and lookup timing

| Array | Implementation | Reset |
|---|---|---|
| Tags | four 128 × 20 LUT RAMs (MLAB), asynchronous read | none |
| Way valid | one 128 × 4 MLAB, asynchronous read, plus 128 set-valid flops | set flops clear |
| LRU ranks | one 128 × 8 MLAB, four 2-bit ranks per set | none; seeded on first install |
| Data | four 256 × 128 simple-dual-port M10K RAMs, one per way; row = half line, address `{set, word[2]}` | none |

`rtl/ppc_ram_lut.sv` and `rtl/ppc_ram_sdp.sv` are the only RAM
descriptions; each pins the RAM style and leaves same-address
read-during-write undefined, which the controller never relies on.

A way is valid when its set-valid flop and its way-valid bit are both set.
Reset and flash invalidation clear the 128 set flops in one cycle.  The first
install into a cleared set writes all four way-valid bits, keeping only the
new way; later installs add their way.  The miss set's valid bits are captured
at lookup, because only the install or an aborting invalidation can change
them.

In the accepting cycle the set index reads all four tags, the way-valid bits
and all four data rows in parallel.  The tag compare yields a one-hot hit that
is registered with word bits `[1:0]`; it feeds only registers (response way,
miss capture, LRU update) and never a RAM address.  The response cycle selects
the word from the registered data outputs with one AND-OR over the one-hot
hit, merged with the refill or error word.

A hit's LRU update is registered and written in the following cycle.  A miss
chooses its victim in `IC_REFILL_REQUEST`, one cycle after the miss, so a hit
accepted just before it has already updated the ranks.  Consecutive updates to
one set read the previous cycle's write.

The data RAMs are read every cycle except while a response is held, so their
outputs stay stable under response backpressure even when a different address
is offered.  Only a refill writes them: the first half-line in
`IC_REFILL_WAIT` as the line is accepted, the second half in `IC_INSTALL` from
a 128-bit holding register.  A read that coincides with a write returns data
that no response selects.  RAM and holding-register contents are not reset.

## Fetch and refill channels

The fetch request is accepted on `fetch_valid_i && fetch_ready_o`.  Its address
is already physical; there is no instruction MMU or permission input.  Ready
requires `IC_IDLE` and either no held response or one being consumed on the
same edge.  A hit produces a held `fetch_rsp_valid_o` response one edge after
acceptance.  Because the next lookup is accepted on the edge that consumes the
response, a requester that keeps a request offered receives one hit per cycle.
Before this change ready also required no held response, capping hits at one
every two cycles.

A miss pulses `miss_o`, captures the address, and offers one line request:

- `line_req_line_addr_o` is the 32-byte-aligned base.
- `line_req_critical_dw_o` is fetch address bits `[4:3]`.
- `line_req_instruction_o` is always one.

The line response layout is identical to [`BUS_LINE_READ.md`](BUS_LINE_READ.md): `[255:192]` is
DW0 through `[63:0]` DW3.  Within each doubleword, the lower-addressed word is
the high 32 bits.  All eight aligned word offsets and all four critical
doublewords are therefore selectable without changing canonical line storage.

A successful response is accepted in one cycle and publishes the requested
word at that edge.  The following `IC_INSTALL` cycle writes the second half,
the tag, validity and the LRU update; the line becomes visible together, and
the next lookup is accepted one cycle after the line.  An error returns a held
zero/error fetch response and does not alter cache storage or LRU state.  This
bounded design waits for the full line.  Section 3.1.2 describes
critical-doubleword forwarding and sequential fetch during fill, including
PID7v behavior; those timing paths remain open.  There is one lookup or refill
in flight, so hits under a refill are also open.

## Kill, invalidate, and reset

`kill_i` cancels an offered refill that has not been accepted.  Once accepted,
the refill transaction cannot be revoked: `line_rsp_ready_o` remains asserted,
the controller drains its response, and neither installs a line nor publishes
a fetch response.  Kill during `IC_INSTALL` suppresses the published response
and the install.  Kill also gates a held fetch response immediately, including
when fetch ready is asserted on that edge.

`invalidate_i` is the bounded flash-invalidate command.  At its sampling edge
all set-valid flops clear.  A held fetch response is suppressed.  An accepted
refill is drained under the same rules as a kill, and an install in progress
is dropped, preventing a same-edge refill from recreating a valid entry.
`invalidate_done_o` acknowledges each sampled command edge; a one-cycle command
therefore yields a one-cycle acknowledgment, while a held command keeps the
acknowledgment asserted after its first sampled edge.  This interface does not
model the two HID0 writes required to set and clear ICFI.

`rst_ni` is synchronous hard reset for cache state and the shared abstract
transport.  It cancels offered or accepted cache activity locally.  System
integration must reset the line transport at the same time; this controller
cannot drain a transaction through reset.

Word-misaligned fetches return a held local error, set sticky
`protocol_error_o`, and create no line request.  A line transport error is a
fetch transport error, not an architectural exception model.

## Standalone synthesis

The standalone Cyclone V storage-inference project is
`quartus/icache/ppc_icache_storage.qsf`; run `./synthesize.sh --docker` from that
directory.  Its gate requires, in the synthesis RAM Summary, four 256 × 128
simple-dual-port M10K data RAMs, four 128 × 20 MLAB tag RAMs and the 128 × 8
LRU and 128 × 4 way-valid MLABs, with no uninferred RAM.  Integrated area and
timing are measured separately by `quartus/integrated`.

Recorded: `quartus/icache/synthesize.sh --docker` (Quartus 17.0.2 `quartus_map`, synthesis only), commit 33c715c, 2026-09-26.

| Standalone `ppc_icache` | Before (c2c84bc) | After |
|---|---|---|
| ALMs needed (estimate) | 8,695 | 1,072 |
| Registers | 11,854 | 352 |
| MLAB memory bits | 0 | 11,776 |
| M10K memory bits | 131,072 | 131,072 |
| Virtual pins / physical I/O | 374 / 0 | 374 / 0 |

These are synthesis estimates, not fitted counts.  The before column reran the
same script on the previous controller, whose tags, validity and LRU were
reset register arrays and whose data was one 512 × 256 RAM (13 M10K blocks in
the last integrated fit).  The four 256 × 128 data RAMs need 4 M10K blocks
each at ×40, so a fit should place 16 blocks; no fit has been run for this
change.

## Files, verification, and limits

`rtl/icache_files.f` lists `ppc_ram_sdp.sv`, `ppc_ram_lut.sv` and
`ppc_icache.sv`.  Integration combines it with the separate
`rtl/line_read_files.f`; neither the scalar bus nor core file list is changed.

`tb/tb_icache.sv` uses the abstract line channel and an independent word/line
oracle.  It checks all eight word positions, all four critical-doubleword
values, request and response backpressure, a directed strict-LRU conflict,
all four possible LRU victims, offered and accepted refill cancellation,
delayed response drain with a repeated invalidation command, same-edge response
kill/invalidate, flash invalidation, refill error, misalignment, and reset
cancellation.  The parent-owned physical integration test connects the
controller to the line master and supplies all refill data through 60x pins.
The storage regression additionally fills all 512 lines with distinct data and
reads every word back in reverse line order, checks one-edge hit latency, and
offers changing addresses while responses are stalled.  This verifies all way,
set and word bits of the RAM paths without inspecting their contents through
hierarchical testbench access.

Streaming checks keep a request offered over the resident image: 200 hits must
return in 201 cycles with every consume edge accepting the next lookup, and
300 more run under random response stalls with changing stalled addresses.
Addresses revisit one set often, chaining LRU updates.  A directed sequence
hits B, A and C on consecutive consume edges and misses E on the next one; E
must evict D, proving the victim sees every registered update.  Another checks
that a refill response consumed during the install cycle is followed one cycle
later by a hit to the new line.

Recorded: `make -C sim test-icache test-icache-managed test-icache-bus60x` (within `make -C sim -j3 regression`, which passed), commit e0d9007, 2026-09-26.
Pass: `tb_icache` 60,883 checks, 5,205 fetches, 4,642 hits, 562 misses, 549
line requests, 500 streamed hits (200 in 201 cycles); `tb_icache_managed` 141
checks; `tb_icache_bus60x` 3,805 checks, 89 fetch responses, 21 bursts.

There is no MMU, translation fault, cache enable/disable bypass, cache lock,
`icbi` address operation, HID0 register, early restart, snooping, parity,
hit-under-miss, or core integration in this bounded controller.  Only one
lookup is outstanding; streaming comes from accepting on the consume edge.
