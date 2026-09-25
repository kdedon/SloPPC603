# Bounded 60x scalar bus master

`rtl/ppc_bus60x.sv` is an executable 64-bit 60x-bus adapter for the core's
scalar data-memory request/response interface.  It is a single-outstanding,
uncached, non-burst foundation.  The implementation serializes each address
tenure before its data tenure; it does not implement cache-line traffic,
address/data pipelining, snooping, parity, global transactions, DBWO, the
32-bit bus mode, or a complete physical MPC603e pinout.

The primary source is the local *MPC603e & EC603e RISC Microprocessors User's
Manual*, `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`
(MPC603EUM/AD, 11/97).  Page references below give physical PDF and printed
page numbers.  [`docs/references/BUS_SPEC.md`](references/BUS_SPEC.md) and [`docs/references/BUS_ADDRESSING.md`](references/BUS_ADDRESSING.md) retain the
broader source transcription and its unresolved editorial details.

## Core-side contract

The request channel is `req_valid_i`/`req_ready_o`.  A request contains
`req_instruction_i`, `req_write_i`, a word-aligned `req_addr_i`,
`req_wdata_i`, and the core's big-endian four-bit byte mask `req_wstrb_i`.
The accepted data masks are:

| Mask | Transfer | Bus address adjustment | `TSIZ` |
|---|---:|---:|---:|
| `1000`, `0100`, `0010`, `0001` | 1 byte | 0, 1, 2, 3 | `001` |
| `1100`, `0011` | 2 bytes | 0, 2 | `010` |
| `1111` | 4 bytes | 0 | `100` |

This matches UM Table 8-1 and the 64-bit lane tables in §8.3.2.4, PDF
322–324 / printed 8-14–8-16.  The current core supplies these scalar masks for
loads as well as stores.  A read response places only requested bytes in their
corresponding positions of the aligned 32-bit response and clears other byte
positions.  This lets the core's load unit apply its signed/unsigned scalar
extraction without relying on values from unselected physical lanes.

An unaligned core address, zero mask, or any other mask is rejected locally:
the adapter produces an error response, performs no bus request, and sets the
sticky `protocol_error_o` diagnostic.  A response remains stable while
`rsp_valid_o` is asserted and `rsp_ready_i` is negated.  No second request is
accepted until the response is consumed.

`rsp_error_o` reports either `TEA` or a malformed bounded-profile exchange.
`protocol_error_o` is sticky until reset and distinguishes local request-shape
errors and malformed bus sequences from a target's valid `TEA` termination.
`busy_o` covers all request, tenure, confirmation, and held-response states.
An instruction request must be a read with mask `1111`; instruction writes and
narrow instruction requests are rejected by the same local-error path.  The
unified router in [`docs/BUS_INTEGRATION.md`](BUS_INTEGRATION.md) generates only this legal shape.

## Pin representation and fixed profile

All bus control names ending in `_n` use active-low pin polarity.  Bidirectional
groups have separate resolved inputs and local output/output-enable signals:
`abb_n_i` with `abb_n_o`/`abb_oe_o`, and `dbb_n_i` with
`dbb_n_o`/`dbb_oe_o`.  Address attributes share `addr_oe_o`; `TS` has its own
`ts_oe_o`; all 64 data pins share `d_oe_o`.  The environment must resolve the
local drives with other bus agents and feed the resolved busy pins back to the
inputs.

The HDL vectors follow PowerPC printed bit order: `a_o[31]` represents `A0`,
and `d_o[63:56]` represents physical byte lane `D[0:7]`.  Thus address
`...000` selects the most significant byte of the HDL data vector and address
`...111` selects the least significant byte.  Unselected write lanes are
driven zero while the selected address and `TSIZ` define which bytes are valid.

The fixed profile drives:

| Signal | Read | Write | Basis |
|---|---|---|---|
| `TT[0:4]` | `01010` | `00010` | cache-inhibited load / cache-inhibited or write-through store, UM Table 7-1, PDF 285–286 / printed 7-9–7-10 |
| `TBST` | negated | negated | one scalar beat |
| `TC[0:1]` | `00` for data, `10` for instruction | `00` | data transaction, instruction fetch, or any write, UM Table 7-6, PDF 290 / printed 7-14 |
| `CI` | asserted | asserted | uncached profile |
| `WT`, `GBL` | negated | negated | no cache/global semantics |
| `CSE[0:1]` | `00` | `00` | one fixed set value; cache-set selection is unused in this profile |

Parity pins and `DBWO` are absent from this bounded interface.  Attributes are
held with the address until the address-bus release completes.

## Address tenure

The master asserts `BR` until it samples a qualified address grant: `BG`
asserted while resolved `ABB` and `ARTRY` are negated.  It then asserts `ABB`
and one-cycle `TS`, holding the adjusted address and attributes until `AACK`.
UM §§8.3.1–8.3.2 and Figure 8-6 define the grant and minimum/wait-extended
address transfer, PDF 318–320 / printed 8-10–8-12.

The cycle after sampling `AACK`, the adapter samples `ARTRY`.  Low `ARTRY`
restarts the complete address transaction after one cycle with `BR` negated,
giving the retrying snooper its documented request opportunity.  An early
`ARTRY` indication that has gone high by this required sample does not cause a
retry: UM §8.3.3 requires a valid early assertion to remain asserted through
the cycle after `AACK`.  These rules and the whole-transaction retry are in
UM §8.3.3 and Figure 8-7, PDF 328–330 / printed 8-20–8-22.

After `AACK`, the adapter drives `ABB` negated from the falling edge through
the following rising edge, then drops `abb_oe_o`, `ts_oe_o`, and
`addr_oe_o`.  This is the implementation's synchronous representation of the
minimum half-bus-clock negation before high impedance.  It is a digital edge
contract, not an AC timing model.

## Data tenure and termination

Once the address is accepted, the adapter waits for a qualified data grant:
`DBG` asserted while resolved `DBB`, `DRTRY`, and associated `ARTRY` are all
negated.  It asserts `DBB` on the next bus cycle.  It drives data for writes and
leaves the data pins undriven for reads.  The qualified-grant equation is from
UM §§7.2.6.1 and 8.4.1, PDF 293 and 330–331 / printed 7-17 and 8-22–8-23.

`TA` may be delayed without a bound.  On writes, a sampled `TA` completes the
beat and `DRTRY` has no cancellation meaning.  On reads, `TA` and data form a
provisional candidate.  In normal DRTRY mode the candidate becomes final only
when `DRTRY` is sampled negated on the following rising edge.  UM §§8.4.4–
8.4.4.1 and Figures 8-9/8-10 specify these rules, PDF 333–335 / printed
8-25–8-27.

If `DRTRY` is asserted at confirmation, the preceding candidate is discarded.
The target may present a replacement with `TA` on that same edge or on a later
edge while `DRTRY` remains asserted.  Every replacement is itself provisional;
consecutive `TA`/`DRTRY` pairs can replace it again.  Negating `DRTRY` without
a previously sampled replacement is diagnosed as malformed.  `DBB` is already
released during an extended final-beat retry, as described in UM §8.4.4 and
Figure 8-12, PDF 333 and 336 / printed 8-25 and 8-28.

`TEA` has priority over `TA` and `DRTRY`.  It returns an error response when
sampled during the live data tenure, during read confirmation, or during an
extended read retry.  A well-formed `TEA` does not set `protocol_error_o`.
The allowed `TEA` window includes the cycle after a read `TA` and an extended
retry after `DBB` release; see UM §§7.2.8.3 and 8.4.4.2, PDF 299 and 337 /
printed 7-23 and 8-29.

After the terminating `TA` or `TEA` sampled while the adapter still owns the
data bus, it drives `DBB` negated from the falling edge through the following
rising edge, then drops `dbb_oe_o` and `d_oe_o`.  Write data remains stable
through that release interval.  UM §7.2.6.3.1 specifies the half-clock DBB
negation, PDF 294 / printed 7-18.

## Reset and compilation

State is reset synchronously on rising and falling clock edges while `rst_ni`
is low.  Bus output enables, `BR`, response-valid, busy, and the protocol
diagnostic are additionally gated to their inactive values directly by
`rst_ni`, so asserting reset releases owned pins without waiting for a clock.
Reset cancels a live transaction or held response; there is no completion for
the canceled request.

`rtl/files.f` remains the CPU core-only compilation list.  The separate
`rtl/bus_files.f` lists this adapter so bus tests and later wrappers can include
it explicitly without adding physical-pin logic to core-only builds.
`rtl/system_files.f` separately lists the unified router and core wrapper;
integration builds combine all three lists.

The task-driven `tb/bfm/bus60x_target_bfm.sv` exposes
`logic [7:0] mem [0:255]` at base address `0x00001000` and schedules controlled
grant, acknowledge, retry, replacement, and error edges.  It supports the
direct adapter test; the full-core integration test uses a separate responder
and architectural memory oracle.

## Verified executable boundary

`tb/tb_bus60x.sv` checks byte, halfword, and word lanes on both halves of the
64-bit bus; arbitrary `BG`, `AACK`, `DBG`, and `TA` waits; grant qualification;
qualified and deasserted-early `ARTRY`; normal, delayed, same-edge, and
consecutive read replacements; `TEA` at the data edge and at `TA+1`; write-side
`DRTRY`; held responses; local malformed requests; malformed DRTRY exchange;
instruction `TC=10` stability across retry; illegal instruction request shapes;
half-clock ABB/DBB release; pin-data stability; and reset cancellation.

This evidence establishes only the bounded adapter profile above.  It is not a
claim of an MPC603e cache/MMU implementation, complete 60x BFM, electrical
timing closure, cache-coherent multiprocessing, burst or pipelined transfer
support, or 32-bit bus-mode support.
