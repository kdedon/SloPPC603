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
initializes distinct LRU values.  `rst_ni` represents that hard-reset behavior:
valids and tags clear and ways receive distinct ranks.  The 128-kbit data array
is deliberately not reset because invalid tags make its contents inaccessible.
The data array is a 512-by-256-bit synchronous-read RAM addressed by the
concatenated two-bit way and seven-bit set. Tags, validity and LRU remain
register arrays. A hit enables the RAM read on the accepting clock edge and
captures the requested word index. The registered RAM output then supplies
the held response. This preserves the existing one-edge hit latency without
an asynchronous array read before the response register.

Only an accepted aligned hit enables a data read. Only a successful refill in
`IC_REFILL_WAIT`, with reset, kill and invalidation inactive, writes the RAM.
The controller cannot read and write it on the same edge, so correctness does
not depend on mixed-port read-during-write behavior. RAM contents and read
output are not reset; reset metadata and response validity prevent publication
of uninitialized or old data. A stalled response blocks subsequent reads,
even when a different address is offered, keeping the selected word stable.

The standalone Cyclone V storage-inference project is
`quartus/icache/ppc_icache_storage.qsf`; run `./synthesize.sh --docker` from that
directory. Its gate requires a full 512-by-256 simple-dual-port RAM entry in
the synthesis report, not merely the presence of a RAM attribute. Integrated
area and timing are measured separately by `quartus/integrated`.

The 2026-09-21 standalone Quartus 17.0.2 synthesis passes with **131,072 block
memory bits**, 11,854 registers, 374 virtual pins and zero physical I/O. The
RAM Summary identifies the complete 512-by-256 `data_mem_rtl_0` as a simple
dual-port RAM. Synthesis estimates 8,695 ALMs for the complete standalone
cache; this is not a fitted resource count. The remaining tag/LRU/control
registers are not claimed to reside in block RAM. The source hashes, complete
report and simulation summary are preserved in
[`quartus/icache/accepted-20260921`](../quartus/icache/accepted-20260921/summary.txt).
No memory-style attribute or substitute storage model was used. The subsequent integrated fitter places
this array in **13 physical M10K blocks**; see the
[current fitted baseline](INTEGRATED_SYNTHESIS_BASELINE.md).

## Fetch and refill channels

The fetch request is accepted on `fetch_valid_i && fetch_ready_o`.  Its address
is already physical; there is no instruction MMU or permission input.  A hit
produces a held `fetch_rsp_valid_o` response containing the selected 32-bit
instruction.  A miss pulses `miss_o`, captures the address and victim, and
offers one line request:

- `line_req_line_addr_o` is the 32-byte-aligned base.
- `line_req_critical_dw_o` is fetch address bits `[4:3]`.
- `line_req_instruction_o` is always one.

The line response layout is identical to `BUS_LINE_READ.md`: `[255:192]` is
DW0 through `[63:0]` DW3.  Within each doubleword, the lower-addressed word is
the high 32 bits.  All eight aligned word offsets and all four critical
doublewords are therefore selectable without changing canonical line storage.

A successful response installs the whole line atomically and returns the
requested word.  An error returns a held zero/error fetch response and does
not alter cache storage or LRU state.  This bounded design waits for the full
line.  Section 3.1.2 describes critical-doubleword forwarding and sequential
fetch during fill, including PID7v behavior; those timing paths remain open.
There is one lookup or refill in flight, so hits under a refill are also open.

## Kill, invalidate, and reset

`kill_i` cancels an offered refill that has not been accepted.  Once accepted,
the refill transaction cannot be revoked: `line_rsp_ready_o` remains asserted,
the controller drains its response, and neither installs a line nor publishes
a fetch response.  Kill also gates a held fetch response immediately, including
when fetch ready is asserted on that edge.

`invalidate_i` is the bounded flash-invalidate command.  At its sampling edge
all valid bits clear and distinct reset LRU ranks are restored.  A held fetch
response is suppressed.  An accepted refill is drained under the same rules as
a kill, preventing a same-edge refill response from recreating a valid entry.
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

## Files, verification, and limits

`rtl/icache_files.f` lists only `ppc_icache.sv`.  Integration combines it with
the separate `rtl/line_read_files.f`; neither the scalar bus nor core file list
is changed.

`tb/tb_icache.sv` uses the abstract line channel and an independent word/line
oracle.  It checks all eight word positions, all four critical-doubleword
values, request and response backpressure, a directed strict-LRU conflict,
all four possible LRU victims, offered and accepted refill cancellation,
delayed response drain with a repeated invalidation command, same-edge response
kill/invalidate, flash invalidation, refill error, misalignment, and reset
cancellation.  The parent-owned physical integration test connects the
controller to the line master and supplies all refill data through 60x pins.
The storage regression additionally fills all 512 lines with distinct data and
reads every word back in reverse line order, checks unchanged hit latency, and
offers changing addresses while responses are stalled. This verifies all way,
set and word bits of the synchronous RAM path without inspecting its contents
through hierarchical testbench access.

There is no MMU, translation fault, cache enable/disable bypass, cache lock,
`icbi` address operation, HID0 register, early restart, snooping, parity,
multi-request hit pipeline, or core integration in this bounded controller.
