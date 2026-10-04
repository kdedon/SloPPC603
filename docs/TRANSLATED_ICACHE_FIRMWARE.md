# Compiled firmware through the translated instruction cache

Recorded: `make -C toolchain rtl-table-search-cached rtl-table-fault-cached`, commit f531cf2 plus uncommitted changes (the IBAT0 I=1 firmware change), 2026-10-04.

The `table-search` and `table-fault` ELF files are the ones the flat and
scalar 60x tests run. `tb_compiled_table_cached_bus60x_firmware.sv` runs each one
through `ppc_core_bat_cached_bus60x` and a single physical 192 KiB RAM at
`0xfff00000..0xfff2ffff`. The RAM model reads and writes only from the public
60x address, control, and data pins. Hierarchical signals serve as read-only
oracles for page-miss retirement, PTE search, TLB fill, and exception state.

The target distinguishes cache-inhibited scalar accesses (`TBST_N=1`,
`CI_N=0`, `TT=01010/00010`) from cacheable instruction-line reads
(`TBST_N=0`, `CI_N=1`, `TT=01110`, `TSIZ=010`). A line address is the critical
doubleword; the responder supplies four 64-bit beats in
`(start[4:3] + beat) mod 4` order within its 32-byte line. Reads come from
physical RAM bytes, and scalar byte/halfword/word stores update RAM only at
accepted `TA` from the external write-data lanes. Address and data grants have
independent waits from `tb/bfm/bus60x_delay_target_bfm.sv`. The test never fabricates an instruction or data response
from the wrapper's internal physical-request wires.

The `table-search` profile checks four exact primary/secondary PTEG scans,
selected PTE1 reads, byte/halfword R/C writes through bus lanes, and completed
RAM update before TLB fill. It checks the full-EA miss capsules, the resident
way-one C=0 retry, and final physical data words. The `table-fault` profile
checks all 21 cases: full search order, 11 allowed fills, 10 ordinary ISI/DSI
vectors, DAR/DSISR/SRR1 records, unchanged normal CR and all 32 normal GPRs at
vector entry, and no PTE write, TLB fill, or denied physical target access on
failure. Vector entry is observed at the retirement of the vector's first
instruction, since vector fetches may hit the cache. Both profiles require
actual line bursts, scalar instruction bypasses, and cache hits.

Only WIMG I selects the bypass path (UM 5.2). Real-mode fetches (WIMG=0001:
startup, miss handlers, vectors) and the search profile's WIMG=0 probe page
fill the cache. Both firmwares map their translated code through IBAT0 with
I=1, so it takes the scalar cache-inhibited path.

Focused strict `-Wall --assert` runs:

| ELF | Retirements | Page misses | Line bursts / beats | Scalar instruction bypasses | Cache hits | Cycles | Checks |
|---|---:|---:|---:|---:|---:|---:|---:|
| `table-search` | 5,154 | 4 | 46 / 184 | 2,579 | 3,587 | 66,658 | 443,463 |
| `table-fault` | 73,466 | 21 | 49 / 196 | 74,706 | 7,752 | 1,495,469 | 9,941,772 |

An earlier run on the unmodified ELFs made two negative images by changing one linked handler instruction while
keeping every other ELF byte and the same pin responder. Replacing the search
handler's R/C write caused rejection at the TLB fill's completed-bus-write
check. Replacing the guarded ISI cause constant with the PP cause caused
rejection at the ordinary vector's SRR1 check.

This establishes the bounded physical instruction-cache transport and the
firmware's existing translation/exception behavior together. It does not
implement automatic code coherence, decoded cache maintenance, a data cache,
or architectural conversion of 60x transport errors into page exceptions.
