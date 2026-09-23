# Bounded 60x line-read master

`rtl/ppc_bus60x_line_read.sv` is a separate synthesizable 64-bit 60x master
for one cacheable 32-byte line read.  It transfers one real four-beat burst;
it does not synthesize a line from four scalar bus transactions.  The scalar
master and unified scalar core wrapper are unchanged and remain described by
`docs/BUS_MASTER.md` and `docs/BUS_INTEGRATION.md`.

The source is the local *MPC603e & EC603e RISC Microprocessors User's Manual*,
MPC603EUM/AD, 11/97.  Table 8-1 and Table 8-2 were checked in the rendered
manual at PDF 322 / printed 8-14.  Figures 8-12 and 8-13 and their surrounding
DRTRY/TEA prose were checked at PDF 336–337 / printed 8-28–8-29.  Extracted
text alone was not used to infer waveform edge values.

## Request and response

The request channel contains:

- `req_line_addr_i[31:0]`: the canonical 32-byte line base.  Bits 4:0 must be
  zero.
- `req_critical_dw_i[1:0]`: which doubleword is transferred first.
- `req_instruction_i`: selects instruction rather than data transfer code.
- `req_valid_i`/`req_ready_o`: one accepted request at a time.

The physical address is `req_line_addr_i + 8*req_critical_dw_i`.  Its low
three bits are always zero, matching the Table 8-2 note.  A misaligned line
base produces a held local error response, sets sticky `protocol_error_o`,
and causes no bus activity.

The response is held on `rsp_valid_o`/`rsp_ready_i`.  `rsp_line_o[255:192]`
is canonical DW0, `[191:128]` is DW1, `[127:64]` is DW2, and `[63:0]` is DW3.
Physical critical-first order is therefore normalized before publication.
`rsp_error_o` publishes no partial line: its data value is zero.  A response
or live transaction blocks another request.

## Critical-doubleword order

UM §8.3.2.3 says a burst read starts with the critical doubleword and may wrap
around the end of the cache line.  Table 8-2 gives the complete 64-bit order:

| Critical index / starting A[27:28] | Beat 0 | Beat 1 | Beat 2 | Beat 3 |
|---:|---:|---:|---:|---:|
| `00` | DW0 | DW1 | DW2 | DW3 |
| `01` | DW1 | DW2 | DW3 | DW0 |
| `10` | DW2 | DW3 | DW0 | DW1 |
| `11` | DW3 | DW0 | DW1 | DW2 |

The implementation uses `(critical index + confirmed beat number) mod 4` to
select the canonical response slot.  Only a DRTRY-confirmed candidate advances
the confirmed beat number.

Figure 8-19 prose at PDF 344 / printed 8-36 calls the first read beat the
“critical quad word,” while §8.3.2.3 and Table 8-2 consistently define a
critical doubleword and four 64-bit beats.  This bounded interface follows the
explicit Table 8-2 order and retains that wording conflict here rather than
reinterpreting the response width.

## Address attributes

The captured request drives one fixed cacheable, non-global line-fill profile:

| Attribute | Driven value | Source basis |
|---|---|---|
| `TT[0:4]` | `01110` Read-with-intent-to-modify | UM Table 7-1, PDF 285–286 / printed 7-9–7-10, lists load miss, store miss, and instruction fetch sources |
| `TBST` | asserted | actual burst transaction |
| `TSIZ[0:2]` | `010` | UM Table 8-1: asserted TBST with `010` is the eight-word/32-byte burst |
| `CI` | negated | cacheable line allocation profile, UM §7.2.4.5, PDF 290 / printed 7-14 |
| `WT`, `GBL` | negated | bounded write-back, non-global profile |
| `TC[0:1]` | `10` instruction, `00` data | UM Table 7-6, PDF 290 / printed 7-14 |
| `CSE[0:1]` | `00` | fixed bounded set value; no cache set is implemented |

The address and attributes remain stable through `AACK` release.  This module
does not claim to derive WIMG state, perform a cache lookup, acquire coherency,
or choose a cache replacement set.  A future cache/MMU must request this
profile only when its own policy makes the transaction appropriate.

## Address tenure and retry

Address arbitration matches the scalar master's source-backed contract.  `BR`
requests the bus; `BG` is accepted only while resolved `ABB` and `ARTRY` are
negated.  The master then asserts `ABB` and one-cycle `TS`, and holds address
and attributes until `AACK`.  It samples `ARTRY` on `AACK+1`.  A qualified
retry aborts the entire transaction, inserts the documented one-cycle `BR`
suppression opportunity, and repeats the same critical starting address.

This is the serialized subset of UM §§8.3.1–8.3.3, PDF 317–330 / printed
8-9–8-22.  No data grant is accepted until the `AACK+1` retry decision, so a
legal address retry cannot leave partial response state.  `ABB` is driven
negated for the falling-to-rising half cycle before its output enable drops.

## Four-beat data tenure

`DBG` is accepted only while resolved `DBB`, `DRTRY`, and associated `ARTRY`
are negated.  The master then asserts `DBB` for one read tenure and never
drives the data pins.  `TA` may be withheld for any number of wait cycles;
four confirmed beats are required.  Adjacent asserted-TA cycles are supported:
at one rising edge, negated `DRTRY` can confirm beat N while asserted `TA`
captures the provisional candidate for beat N+1.

Every read candidate remains provisional through the following `DRTRY`
sample.  Asserted `DRTRY` discards that candidate without advancing the line.
`TA` on the same edge supplies a replacement for the discarded logical beat;
otherwise `DRTRY` may remain asserted while replacement data is delayed.  A
replacement is itself provisional and can be replaced repeatedly.  Negating
`DRTRY` without a captured replacement is diagnosed as malformed.

These rules follow UM §§8.4.4–8.4.4.1 and Figures 8-11–8-13, PDF 333–337 /
printed 8-25–8-29.  Figure 8-13 visibly includes TA pacing and a burst-beat
DRTRY replacement; the implementation does not assign unlabeled waveform
polygons to additional architectural beat identities.

The final provisional `TA` starts the documented DBB release, but the 256-bit
response remains unavailable until the next-cycle DRTRY confirmation.  If
that final candidate is canceled, replacement and repeated replacement occur
with this master's `DBB` already released while DRTRY continues bus-mastership
exclusion.  A later low `TA` on the successful final-confirmation edge is not
qualified by this released tenure and cannot poison the captured final beat;
only `DRTRY` and `TEA` judge it.

`TEA` has priority at any active beat, confirmation edge, or extended final
retry.  It truncates the line and returns an error with zero response data.
A well-formed target `TEA` does not set `protocol_error_o`.  UM §8.4.4.2,
PDF 337 / printed 8-29, explicitly permits TEA while DBB and/or DRTRY is
asserted.  Architectural machine-check behavior remains outside this module.

## Reset, files, and verification

Reset cancels the request, partial line, final confirmation, and held response.
Output enables and externally visible valid/busy/diagnostic signals are gated
inactive while `rst_ni` is low.  ABB and DBB release use the same bounded
falling-edge half-cycle representation as the scalar master; this is a digital
protocol contract rather than an AC timing model.

`rtl/line_read_files.f` contains only this module.  It remains separate from
the scalar `rtl/bus_files.f` and unified-core `rtl/system_files.f` lists.

`tb/bfm/bus60x_line_target_bfm.sv` is a task-driven source of explicitly
scheduled grants, acknowledgments, beats, retries, and errors.
`tb/tb_bus60x_line_read.sv` checks all four literal Table 8-2 starts, canonical
response placement, adjacent beats, address retry, a replaced third beat,
extended and replaced final beat after DBB release, unqualified final-edge TA,
ABB/DBB half-cycle release, nonfinal-TA DBB retention, external bus and retry
grant exclusion, TEA truncation, malformed early DRTRY, held response
stability, invalid line alignment, and reset cancellation.

This is line-refill transport groundwork only.  There is no cache array, tag,
replacement policy, WIMG derivation, coherence engine, eviction, store burst,
critical-word forwarding, 32-bit bus mode, parity, or integration with the
current core.
