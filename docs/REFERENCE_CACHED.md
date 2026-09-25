# Original-handler comparison through the cached CPU

`make -C sim test-reference-cached` runs the fixed memory corpus through
`ppc_core_cached_bus60x`. It compares 9,881 retired instructions covering all
168 implemented forms against the original DingusPPC handlers. Every snapshot
includes all GPRs, CR/XER/LR/CTR and all 256 bytes of test RAM, using the existing
102-field v2 format. It does not add instruction implementations.

The independent `tb_core_cached_reference.sv` RAM responder chooses instruction
and data values solely from physical address, TC, transfer type/size, data and
acknowledgment pins. Instruction transfers must be four-beat cacheable bursts;
data transfers must be scalar reads/writes. A literal critical-doubleword order
table selects instruction data. Byte stores update only their physical lanes.
The bench varies bus grants and acknowledgments and stalls retirement. Core
signal taps count fetches and export architectural state; they do not choose
memory responses or interpret instructions.

The instruction image is immutable and separate from the 256-byte big-endian
data RAM, including where numeric addresses overlap. This is the same explicit
Harvard test model used by the fixed memory reference. It does not verify
self-modifying code, shared instruction/data coherency, BAT/TLB translation,
precise exceptions or cycle conformance. The architectural handler oracle does
not model cache timing or bus arbitration; separate pin and ownership tests
cover those behaviors.

## Accepted evidence

- 9,881 retirements and all 168 implemented forms match.
- 9,992 accepted fetch requests: 8,755 cache hits and 1,237 misses/burst addresses.
- 240 scalar data transactions, including 134 stores.
- 15,844 physical bus wait cycles and retirement backpressure.
- Three injected GPR/RAM corruptions are rejected by the public v2 comparator.
- All 142 source, header, executable and trace hashes in the final manifest match.

These counters stop at the final required retirement; speculative fetch may
still have an outstanding burst. They are workload observations, not processor
performance or whole-bus-idle acceptance claims. The existing fixed and seeded
reference lanes remain available independently.

`sim/build/reference-cached/manifest.json` records the exact commands, sources,
reference checkout identity, coverage, diagnostics and hashes. `program.hex`,
`expected.txt`, `actual.txt`, the executables and the original license/credits
are retained there. Regenerable compiler header caches are removed by the runner
only from its own compiler directory after execution finishes.

## Managed-cache profiles (round 38)

The same independent physical-pin responder and original-handler comparison
also support `--cache-profile managed` and `--cache-profile disabled`. The first
uses `ppc_core_cached_bus60x_managed` with its local cache-enable reset parameter
set. The second starts that wrapper in scalar instruction bypass mode. Each
profile gets its own build directory and manifest, including the profile name,
exact compiler defines, sources, original headers, executable and trace hashes.

```sh
make -C sim test-reference-managed
make -C sim test-reference-cache-disabled
```

The bypass responder derives instruction data lanes from the captured physical
address and checks instruction TC, cache-inhibit, single-beat size/type and read
output-enable behavior. It requires zero hits, misses and bursts. The enabled
profiles require cache hits and fewer instruction bursts than accepted fetches.
Both retain all architectural register/RAM comparisons, retirement backpressure,
physical wait cycles and three deliberately corrupted trace checks.

These fixed workloads do not issue maintenance commands. Changed-code visibility
and maintenance drain/turnover belong to the dedicated cache-control tests.
Neither profile enables the opt-in supervisor instructions or constitutes an
exception/MMU/timing oracle. Bus work may still be speculative at the final
recorded retirement, so final counters do not imply a drained system.

Round 38 acceptance: all three profiles matched **9,881 retirements**, all
**168 default forms**, and every word of the 256-byte data RAM. Each rejected
three injected register/RAM corruptions. Final source/header/binary/trace hashes
match all retained manifests (143 legacy, 149 managed, 149 disabled).

| Profile | Accepted fetch requests | Cache hits | Miss/burst addresses | Scalar instruction addresses | Scalar data / stores | Physical wait cycles |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Original cached wrapper | 9,992 | 8,755 | 1,237 | 0 | 240 / 134 | 15,844 |
| Managed, cache enabled | 9,992 | 8,755 | 1,237 | 0 | 240 / 134 | 15,856 |
| Managed, cache disabled | 9,922 | 0 | 0 | 9,922 | 240 / 134 | 91,446 |

The independent responder accepted 5,184 / 5,188 / 10,161 data beats respectively
before the final required retirement. These endpoint-dependent counts include
speculation and outstanding transport, so they are not drained-system totals
or a 603e performance comparison. Artifacts are retained under
`sim/build/reference-cached`, `sim/build/reference-managed`, and
`sim/build/reference-cache-disabled`; completed compiler header caches are
removed without deleting the executables, manifests or traces.
