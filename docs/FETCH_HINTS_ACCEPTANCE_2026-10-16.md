<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Fetch classification companions: staged acceptance

Recorded: `lint check-spec`, enabled `test-core-bat-cached-bus60x` and `test-chip-pins`, and Quartus 17 analysis/elaboration, commit 20c0bdf plus the default-off fetch-hint implementation, 2026-10-16.

This is an experimental checkpoint. Newly canonicalized fixtures and ownership diagnostics still need their connected rerun. There is no new physical fit, frequency improvement or release acceptance claim.

## Change

The measured frontend path includes fetch resource classification and CR rename demand. `ENABLE_FETCH_HINTS=1` computes their existing predicates before cache storage and carries three bits with each word: `{raw CR demand, branch class, needs_IU}`. `ppc_fetch_hints` uses the actual stateless decoder for eight line words and the scalar response, with all decoder configuration parameters bound. The original `cr_writer` predicate moved unchanged to the shared package.

The feature defaults to zero. It adds no capture edge or instruction latency. IQ payloads, resource capacities, allocation, retirement, branch policy, valid/ready authority and precise exceptions retain their existing behavior. The original full instruction decode still supplies execution.

The generic cache keeps `ENABLE_METADATA=0` and `WORD_META_BITS=2` defaults. The enabled CPU assembly chooses three bits per word, producing a 140-bit row containing four instruction words and their twelve companion bits. Disabled rows remain 128 bits. Data and companions share the same RAM address, enable, half-line capture and selected response owner. The accepted INSTALL-abort victim invalidation remains in place.

## Accuracy boundaries

The all-zero word has hint value zero in both supervisor profiles. With supervisor exceptions enabled, it decodes as `SPECIAL_PROGRAM_ILLEGAL` without CR demand; with them disabled it remains illegal. Router arms that replace the instruction with zero also replace its hints with zero. Other faults retain raw hints until the existing consumer gates apply.

Class suppression keeps its procedural fault priority. Lane 0 CR demand keeps `(queued.fault == FETCH_OK) && raw_writer`. Lane 1 keeps its original `FETCH_WIDTH == 2 && raw_writer` gate, including its absence of a new fault gate. IABR handling, FW1 dummy-lane classification and FD split/promotion retain their original semantics.

The transport claim applies to reset-initialized, protocol-legal executions with known owner/address/control selections. Arbitrary unknown selectors are not equivalent: merging two words before nonlinear decoding can differ from merging their precomputed hints. Enabled simulation diagnostics report unknown accepted addresses, maintenance controls and response/buffer/FD owners. Existing end-to-end assertions compare the hints against the actual original decoder at meaningful FD lanes. None of these checks assumes failures away or rejects an instruction merely because its payload contains unknown bits.

Meaningful RAM responses additionally require an initialized selected row, one selected owner and no undefined selected read-during-write collision. Finite row-monitor tests support those obligations; they are not a proof over every interleaving or corrupted multiway state. No universal four-state equivalence claim is made.

## Completed checks before the canonical rerun

| Check | Result | Scope |
| --- | --- | --- |
| Default strict lint and specification checks | Pass | 190 rows, 41 rules, 391 locators; 259 tool and 29 cosimulation Python checks |
| Enabled strict lint | Pass | DW2/FW2/LSU1, FPU disabled and enabled |
| Enabled translated cached bench | Pass | FW1, FD0; 1,729 checks, 41 retirements, 14 address transactions, 7 line fills, 54 hits, 7 misses, 5 bypasses, one data read and write |
| Enabled package pins | Pass | FW2, FD0; 2,596 checks, 398,726 cycles, 1,767 streamed fetches; reset, locked bypass, faults and interrupt priorities |
| Quartus 17 analysis/elaboration | Pass | CPU-only enabled profile; 0 errors, 62 warnings, 43 seconds; no physical timing result |
| Preparatory opaque cache matrix | Pass | 24 profiles: three geometries, FW1/2, metadata off/on and two/three-bit width; original public control comparisons plus independent word/metadata oracles |
| Preparatory selected-row monitor | Pass | 12 profiles, two-bit metadata only; every way and both halves, held/scalar/reset paths, initialized selected row and selected-collision checks |

Initial opaque-fixture attempts failed before simulation on strict testbench width/unused diagnostics. Explicit projections repaired the fixture while preserving the original two-bit producer semantics and all mandatory public word/control checks. The final three-bit matrix passed. Its opaque values test transport, not ISA classification.

The row monitor snapshots initialization before the actual read/write edge and retains its read certificate while RAM reads are held. It allows and counts collisions on unselected rows. Its two-bit result is not relabeled as a 140-bit assembled-row proof.

## Reproduction and adoption gates

Canonical optional entry points run the existing benches and their unchanged golden/manual checks serially, with named enabled profiles and separate outputs:

```sh
make -C sim -j1 test-fetch-hints FETCH_HINTS_PROFILE=focused
make -C sim -j1 test-fetch-hints-cached
make -C sim -j1 test-fetch-hints-package
make -C sim -j1 benchmark-integer-fpu-pair INTEGER_PAIR_HINTS=1
```

The benchmark requires the pinned Dhrystone image/dump already described by its accepted measurement contract. It compares all normalized active retirement fields, verifies actual architectural RAM initialization, and keeps the original firmware checks. Both enabled arms must also match the earlier hint-disabled full stream, cycle totals and counters exactly before claiming cycle preservation. The new report field identifies the actual hint setting; it does not mask any architectural field.

Before adoption, rerun the canonical metadata fixture and source guard, connected cached maintenance/drain/coherence/IRQ and package FW2/FPU profiles, supported fault/endian/refetch and held/pair/FD paths. Keep untested profiles explicit. Full combined CI and FPU/manual acceptance remain separate gates.

A matched physical fit must then establish all-corner setup/hold and unconstrained coverage, actual widened-RAM packing, and identical baseline clock/profile choices. Keep the feature separate if it regresses timing. Do not change instruction accuracy, numerical/manual cycle expectations or SDC exceptions to obtain a frequency number.
