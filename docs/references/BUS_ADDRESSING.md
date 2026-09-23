# Bus address, size, and physical lane decomposition

This document records a bounded, queryable transcription of MPC603e User's
Manual Tables 8-4 through 8-7. It describes bus-transfer addresses, transfer
sizes, data-beat counts, and the physical bus lanes marked by those tables. It
does not assign operand bytes to lanes or select an endian mode.

## Sources and notation

The primary source is the MPC603e User's Manual:

- Section 8.3.2.4, Table 8-4, “Aligned Data Transfers (64-Bit Bus),” PDF
  pages 323–324, printed pages 8-15–8-16.
- Section 8.3.2.4, Table 8-5, “Misaligned Data Transfers (Four-Byte
  Examples),” PDF page 325, printed page 8-17.
- Section 8.3.2.5, Table 8-6, “Aligned Data Transfers (32-Bit Bus Mode),”
  PDF page 326, printed page 8-18.
- Section 8.3.2.5, Table 8-7, “Misaligned 32-Bit Data Bus Transfer
  (Four-Byte Examples),” PDF page 327, printed page 8-19.
- Section 7.2.7.1, Table 7-7, PDF page 295, printed page 7-19, maps lane
  numbers to `DH` and `DL` signal slices. Section 8.6.1, PDF page 346,
  printed page 8-38, limits 32-bit mode to lanes 0–3 (`DH[0:31]`).
- Section 8.3.2.2, PDF page 322, printed page 8-14, supplies the separate
  32-byte coherency-boundary rule reported by the query.

Bit strings preserve the manual's MSB-first numbering. `A[29:31]` is the low
three bits of an already bus-side byte address. `TSIZ[0:2]` encodes the size of
the program transaction or bus transfer as shown in the selected row.

`source_table_lane_marks` contains only the columns marked `A` in the rendered
table. For Tables 8-6 and 8-7, `source_table_lane_cells` also preserves every
printed `A`, em dash, `x`, and anomalous blank. The lane numbers identify
physical signal groups:

| Lane | Physical data signals |
|---:|:---|
| 0 | `DH[0:7]` |
| 1 | `DH[8:15]` |
| 2 | `DH[16:23]` |
| 3 | `DH[24:31]` |
| 4 | `DL[0:7]` |
| 5 | `DL[8:15]` |
| 6 | `DL[16:23]` |
| 7 | `DL[24:31]` |

This mapping says which pins participate. It does not say which operand byte
is most or least significant, translate a CPU effective address, or define
memory-controller endian steering.

## Tables 8-4 and 8-6: aligned transfers

The transcription contains all 15 aligned request rows for each width.

| Request bytes | Valid A[29:31] | 64-bit marked lanes, Table 8-4 | 32-bit marked lanes, Table 8-6 | 32-bit beats |
|---:|:---|:---|:---|---:|
| 1 | `000`–`111` | lane numbered by `A[29:31]` | lane `A[30:31]`, so lanes 0–3 repeat for `100`–`111` | 1 |
| 2 | `000`, `010`, `100`, `110` | `[0,1]`, `[2,3]`, `[4,5]`, `[6,7]` | `[0,1]`, `[2,3]`, `[0,1]`, `[2,3]` | 1 |
| 4 | `000`, `100` | `[0,1,2,3]`, `[4,5,6,7]` | `[0,1,2,3]` for either address | 1 |
| 8 | `000` | `[0,1,2,3,4,5,6,7]` | `[0,1,2,3]` on both beats | 2 |

Table 8-6 describes the doubleword as one data transaction requiring two data
beats. Both printed beat rows retain `TSIZ=000`, `A[29:31]=000`, and lanes
0–3. The query reports one access with two explicit four-byte beat records. It
does not invent a second address because the table does not provide one.
Section 8.3.2.5 limits this generated doubleword case to the 603e floating-point
load/store double operations and says it is unsupported on the EC603e. The
query is a table-row lookup and does not decide instruction legality.

## Tables 8-5 and 8-7: four-byte decomposition

Both tables give every possible starting `A[29:31]` for a four-byte request. A
request crossing a four-byte word boundary splits at that boundary. The
addresses below are relative to the requested bus-side address.

| Start | First access | Second access | 64-bit lanes (8-5) | 32-bit lanes (8-7) |
|:---:|:---|:---|:---|:---|
| `000` | +0, 4 B, `TSIZ=100`, `A=000` | — | `[0,1,2,3]` | `[0,1,2,3]` |
| `001` | +0, 3 B, `TSIZ=011`, `A=001` | +3, 1 B, `TSIZ=001`, `A=100` | `[1,2,3]`; `[4]` | `[1,2,3]`; `[0]` |
| `010` | +0, 2 B, `TSIZ=010`, `A=010` | +2, 2 B, `TSIZ=010`, `A=100` | `[2,3]`; `[4,5]` | `[2,3]`; `[0,1]` |
| `011` | +0, 1 B, `TSIZ=001`, `A=011` | +1, 3 B, `TSIZ=011`, `A=100` | `[3]`; `[4,5,6]` | `[3]`; `[0,1,2]` |
| `100` | +0, 4 B, `TSIZ=100`, `A=100` | — | `[4,5,6,7]` | `[0,1,2,3]` |
| `101` | +0, 3 B, `TSIZ=011`, `A=101` | +3, 1 B, `TSIZ=001`, `A=000` | `[5,6,7]`; `[0]` | `[1,2,3]`; `[0]` |
| `110` | +0, 2 B, `TSIZ=010`, `A=110` | +2, 2 B, `TSIZ=010`, `A=000` | `[6,7]`; `[0,1]` | `[2,3]`; `[0,1]` |
| `111` | +0, 1 B, `TSIZ=001`, `A=111` | +1, 3 B, `TSIZ=011`, `A=000` | `[7]`; `[0,1,2]` | `[3]`; `[0,1,2]` |

For example, a four-byte request at `0x00001003` becomes one byte at
`0x00001003` followed by three bytes at `0x00001004`. In 32-bit mode those
transfers use physical lane 3 and lanes 0–2, respectively. The query does not
label the values carried by those lanes as big-endian or little-endian bytes.

## Preserved source anomalies

The rendered tables contain four apparent editorial anomalies. The manifest
retains the raw value and records each provisional normalization:

- Table 8-5, start `010`, second access prints `TSIZ=011` although it marks two
  lanes. Table 8-1, the mirrored `110` case, and Table 8-7 support provisional
  `TSIZ=010` normalization used by the query.
- Table 8-6, byte start `001`, lane 2 prints `x`. The note defines `x` as a
  lane unavailable in 32-bit mode, but lane 2 is within `DH[0:31]` and is used
  by the next byte row. The raw `x` is retained and provisionally normalized
  to an unused em dash.
- Table 8-7, start `001`, first access leaves lane 0 blank even though the note
  defines no blank symbol. It is retained and provisionally normalized to an
  unused em dash.
- Table 8-7, start `010`, second access prints `x` in lane 3 even though lane 3
  is within `DH[0:31]`. It is retained and provisionally normalized to an
  unused em dash.

The last three anomalies do not change active-lane results because active
lanes are derived only from the printed `A` marks. Queries that touch an
anomalous row return `defined_with_explicit_source_conflict` and include its
normalization record.

## Query contract

The machine-readable source is `sim/spec/bus_addressing.json`. The tool accepts
an already bus-side 32-bit unsigned byte address, a size of 1, 2, 4, or 8
bytes, and a 32- or 64-bit bus width:

```sh
python3 sim/tools/bus_address.py validate
python3 sim/tools/bus_address.py query --address 0x00001003 --size 4 --bus-width 32
python3 sim/tools/bus_address.py query --address 0x00001000 --size 8 --bus-width 32
```

Each access identifies the exact source table, physical lane marks, and active
`DH`/`DL` signal slices. An aligned four-byte result cites both its aligned and
four-byte-example tables in `source_table_rows`; `source_table` identifies the
four-byte decomposition row used to construct the access. Top-level fields
make the boundary explicit:

- `address_domain` is `already_bus_side_32_bit_byte_address`.
- `lane_result_scope` covers physical signal groups marked by the table.
- `operand_byte_to_lane_mapping` is not provided.
- `endian_lane_steering` remains outside scope.
- `cpu_access_to_bus_prediction` requires cacheability and memory-hierarchy
  context.

The output describes selected nonburst bus decomposition. Section 8.3.2.4
explains that many misaligned accesses hit in cache or cause a burst fill.
Section 2.2.3, PDF page 92, printed page 2-14, says each discrete access to a
noncacheable page produces an individual bus operation. These sources do not
justify directly converting an arbitrary CPU effective address into the
reported external transfers.

A request at `0x0000001f` crosses an aligned 32-byte boundary. The query reports
Section 8.3.2.2's requirement to present a new address at the boundary or treat
the data as noncoherent with respect to the 603e.

Run the focused checks from `ppc603e/`:

```sh
python3 -m json.tool sim/spec/bus_addressing.json >/dev/null
python3 sim/tools/bus_address.py validate
python3 -m unittest -v sim/tools/test_bus_address.py
```

The validator reconstructs every selected table row and raw 32-bit lane cell,
checks primary-source provenance and scope statements, and requires exact
counts. Tests query every aligned row and every four-byte start for both
widths, check the two-beat doubleword representation, verify all physical
`DH`/`DL` mappings, preserve all four source anomalies, reject malformed
queries, and reject targeted metadata mutations.

## Deliberate limits

The selected tables do not cover non-four-byte misaligned requests. The
contract also leaves operand byte significance, endian steering, CPU
address translation, cache/bus prediction, floating-point legality, external
control transaction rules, burst ordering, termination timing, RTL, and BFM
behavior outside scope. For the 32-bit doubleword it reports the two source
beat rows and deliberately supplies no derived second-beat address.
