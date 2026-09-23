# Compiled firmware through the translated instruction cache

The `table-search` and `table-fault` ELF files are unchanged from the accepted
scalar 60x tests. `tb_compiled_table_cached_bus60x_firmware.sv` runs each one
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
independent waits. The test never fabricates an instruction or data response
from the wrapper's internal physical-request wires.

The `table-search` profile checks four exact primary/secondary PTEG scans,
selected PTE1 reads, byte/halfword R/C writes through bus lanes, and completed
RAM update before TLB fill. It checks the full-EA miss capsules, the resident
way-one C=0 retry, and final physical data words. The `table-fault` profile
checks all 21 cases: full search order, 11 allowed fills, 10 ordinary ISI/DSI
vectors, DAR/DSISR/SRR1 records, unchanged normal CR and all 32 normal GPRs at
vector entry, and no PTE write, TLB fill, or denied physical target access on
failure. Both profiles require actual line bursts, scalar instruction bypasses,
and cache hits. Real-mode instruction WIMG is nonzero and bypasses; allowed
translated WIMG=0 instruction fetches may fill the physical cache.

Focused strict `-Wall --assert` runs after the fetch-credit fix passed:

| Unchanged ELF | Retirements | Page misses | Line bursts / beats | Scalar instruction bypasses | Cache hits | Checks |
|---|---:|---:|---:|---:|---:|---:|
| `table-search` | 5,152 | 4 | 41 / 164 | 3,328 | 2,554 | 573,675 |
| `table-fault` | 73,464 | 21 | 85 / 340 | 7,015 | 74,250 | 5,251,837 |

Two negative images were made by changing one linked handler instruction while
keeping every other ELF byte and the same pin responder. Replacing the search
handler's R/C write caused rejection at the TLB fill's completed-bus-write
check. Replacing the guarded ISI cause constant with the PP cause caused
rejection at the ordinary vector's SRR1 check. Their artifacts are under
`/tmp/ppc-table-search-cached-negative.*` and
`/tmp/ppc-table-fault-cached-negative.*`.

This establishes the bounded physical instruction-cache transport and the
firmware's existing translation/exception behavior together. It does not
implement automatic code coherence, decoded cache maintenance, a data cache,
or architectural conversion of 60x transport errors into page exceptions.
