# Deterministic original-handler mixed-program stress

This lane generates seeded mixed programs, executes the original DingusPPC
handlers, and compares every retired instruction against the actual core. It
reuses the accepted v2 flat-memory adapter and actual-core memory reference
bench. The fixed v1/v2 corpora and their formats remain unchanged. See
[REFERENCE_RUNNER.md](REFERENCE_RUNNER.md) for handler provenance, GPL-3.0-or-later
license, compiler policy, closed opcode gate, and the exact 102-field v2 schema.

## Reproduce

From `sim/`:

```sh
python3 cosim/run_reference_stress.py --build-dir build/reference-stress
python3 cosim/run_reference_stress.py --build-dir build/reference-stress \
  --reuse-build --seeds ffffffff --blocks 512 --report-name maximum.json
python3 -m unittest discover -s cosim -p 'test_*.py'
```

The default is three hexadecimal seeds `603e,1,deadbeef`, each with 120 mixed
blocks. `--seeds` accepts 1–32 distinct uint32 hexadecimal values; `--blocks`
accepts 16–512. The first invocation compiles the reference and RTL once and
reuses those executables for every seed. `--reuse-build` requires exact recorded
source and executable hashes. It fails on a stale build rather than rebuilding
silently. `--report-name` permits a separate maximum-size report without
overwriting the default `suite.json`. Per-seed directories include both seed
and block count.

Generation version 1 uses an explicitly defined xorshift32 generator, independent
of Python's random module. The program words, seed, block count and generator
version are recorded. A unit test anchors the SHA-256 of seed 1 / 16 blocks;
changing the generated instruction sequence requires deliberately updating that
anchor and considering a generator-version change.

## Program and oracle scope

Every program initializes data registers and all 256 data-RAM bytes through real
instructions. Its first nine blocks exercise all nine block categories; later
blocks choose among them deterministically:

| Category | Relationships exercised |
|---|---|
| Carry chain | Carry producer, dependent extended arithmetic, unary carry and dependent logical operations; RAW/WAW aliases and Rc/SO propagation |
| Logical/rotate/shift | Random Boolean operation, masked insertion using the old destination, shift and count/sign-extension consumer |
| Multiply/divide | Multiply result consumed by a defined divide and then arithmetic; divisor established by real instructions |
| Memory dependency | Aligned byte/halfword/word store, load and arithmetic consumer, plus nearby data reuse |
| Update aliases | Store source equal to old base, indexed store with base/index/source aliases, load destination equal to old index, and consumers of both updated destinations |
| Conditional branch | Random CR field comparison and legal BO/BI forward branch around one instruction |
| Counted loop | CTR initialized to 1–5, two-instruction dependency body, and backward BDNZ |
| LR/CTR branch | Actual BL/BCLR call and return, then taken BCCTR after an explicit target write; both LK settings |
| CR transfer | Masked CR write, field move, CR logic, MCRXR, extended arithmetic after cleared XER flags, and MFCR readback |

Only original handlers compute expected architectural state. Generator encodings
and constraints do not implement an instruction-state oracle. Dynamic form
coverage is labeled using `isa.json` only after reference execution, and requires
exactly one matching entry for each executed instruction. Each suite records
the precise dynamically covered and uncovered IDs. This is **not** a claim that
the stress corpus covers all 168 implemented forms; that inventory claim belongs
to the separate fixed v2 corpus.

Data RAM is the aligned big-endian interval `0x1000..0x10ff`, initially zero.
The immutable instruction image is separate even where numeric instruction and
data addresses overlap. There is no self-modifying-code, MMU, cache, architectural
fault, external recovery, interrupt or bus-electrical claim. Invalid encodings,
misaligned/out-of-range data accesses, invalid update aliases, zero divisors and
signed minimum divided by minus one remain explicit adapter errors. Stress
division selects a known positive nonzero divisor, so undefined results are not
masked or accepted.

The existing RTL bench varies fetch, memory and retirement backpressure and
checks held transactions. It derives each seed's required retirement/request/
store counts from the executed reference trace, rather than fixed-corpus totals.
Each retirement compares PC/word, all 32 GPRs, full CR/XER/LR/CTR and all 64 RAM
words. Whole memory is compared, not a digest. The bench waits for actual
retirement and tolerates implementation multiply/divide latency; it does not
claim manual cycle timing.

## Bounds and failure evidence

Branches remain within the generated image. The BL/BCLR shape returns to a
forward branch around the return instruction; BCLR with LK reads its old LR
target before writing the new link. BCCTR targets are established immediately
before branching and intentionally include low address bits that the handler
must mask. The only repeated body is the counted loop, which reloads CTR to
1–5 and contains no other CTR writer. Each block emits at most 16 words and retires at most 18 instructions
including loop repetitions. With 222 initialization and three final instructions,
the bound is 9,441 retirements at 512 blocks, well below the adapter's
100,000-instruction guard.
The bench's 500,000-cycle watchdog is retained; passing measured maximum-size
seeds is evidence for these programs, not an exhaustive proof for every seed.

`build-manifest.json` pins original reference revision/dirty status, all local
reference headers, adapter/generator/comparator inputs, canonical RTL and ISA
metadata, compiler commands/versions, and both executable hashes. Source hashes
are checked again after compilation and after the suite. Per-seed manifests
pin program and trace hashes, executed form/kind counts, memory counts, control
outcomes, and exact reproduction commands. They retain the first divergent
row/PC and nearby annotated program instructions on comparison failure.

Each passing seed also corrupts one middle-row GPR and one RAM word independently
and invokes the public v2 comparator against the actual RTL trace. Both must
fail with the precise field diagnostic. Existing comparator tests cover malformed,
empty, truncated and schema-incompatible traces. No expected/actual mismatch is
ignored. A failing seed leaves its program, partial traces and failure manifest
for reproduction. Regenerable Verilator `*.gch` files in this lane's owned build
directory are removed after execution, while binaries, logs, traces and manifests
remain available.

## Measured acceptance

The frozen Round36 source passed on 2026-09-14 with the current iterative
divider and fixed multiplier maxima (MULLI 3, MULLW/MULHW 5, MULHWU 6 cycles).
The stress generator does not emit MULLI; its functional/timing coverage remains
in the separate fixed corpus and multiplier tests.

| Seed | Blocks | Image words | Retirements | Dynamic forms | Memory requests / stores |
|---|---:|---:|---:|---:|---:|
| `0000603e` | 120 | 1,087 | 1,125 | 89 | 178 / 120 |
| `00000001` | 120 | 1,112 | 1,187 | 91 | 186 / 124 |
| `deadbeef` | 120 | 1,031 | 1,107 | 87 | 162 / 112 |
| `ffffffff` | 512 | 3,812 | 4,050 | 104 | 534 / 298 |

The default three-seed suite passed 3,419 snapshots across 104 dynamic forms;
the separate maximum suite passed 4,050 snapshots. Together they compare
**7,469 snapshots × 102 fields**, covering 105 distinct metadata forms with
1,060 memory requests (654 stores and 406 reads). All eight injected
GPR/RAM divergences were rejected with the expected precise field. Both forward
conditional outcomes and taken/final-not-taken counted loops occurred. The
maximum seed alone exercised 105 taken loop backedges, 56 BCLR returns, 56 taken
BCCTR branches, and 289 data-request / 312 instruction-request / 1,667 retirement
stall observations. All 22 cosim unit tests passed.

The default `sim/build/reference-stress/suite.json` and separate `maximum.json`
retain their own per-seed manifest hashes. Both used the same original-handler
and actual-core executables. A final independent hash check found all 126
recorded source inputs and both executables unchanged, and no owned `*.gch`
files remained. Binaries, annotated programs, expected/actual full-state traces,
logs and manifests remain in that build directory.

Five additional reference-only 512-block probes (seeds 0, 1, 603e, deadbeef and
ffffffff) completed with 3,688–3,937 words and 3,980–4,319 snapshots; these probes
establish generation legality only, not additional RTL-comparison acceptance.
