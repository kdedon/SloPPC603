# Special second-port offer control projection

Composition note (2026-10-16): this draft adds the D1 admission cofactor to the exact accepted-bfd plus special-port1 source. The historical standalone results below do not validate the new combination. Fresh accepted-bfd temporal tracing, combined proofs, strict RTL/core gates, Quartus and matched timing remain pending.

Recorded: optional `test-special-port1-offer-proof` recipe, exact RTL from commit `abf9686`, 2026-10-16. In a minimal checkout, source guards, three negative source mutations and all 983,040 Icarus comparisons pass. The full simulation Makefile was not used for this bounded run.

The source tool pins the exact package, candidate core and special-unit contents. Its complete inverse guards pin the original core and special sources, including the state enum. The enum values used by the finite corpus are therefore guarded source facts, not unguarded assumptions about state numbering.

## Control relation

The special unit originally qualifies `result_valid` with cancellation only in `S_MMU_RESULT`. That state cannot offer on port 1: eligibility permits only `S_EXEC` and `S_TIMER_RESULT`. Forming their complete offer directly removes the correlated cancellation dependence while preserving old eligibility, normal results, payload priority, ready signals, state transitions and every rename reader.

Unknown state bits matter. Original procedural result validity defaults to 0 when all state comparisons are unknown. The new offer likewise uses a procedural default of 0; a logical OR of decoded state terms is not equivalent. Known MMU and other ineligible states produce 0 even for unknown cancellation or fault inputs. Port 1's three-way source selection is unchanged.

## Optional reproduction

From this checkout, with optional Icarus installed:

```sh
make -C sim -j1 BUILD_DIR=build-special-port1-proof test-special-port1-offer-proof
```

No firmware, Git history or scratch snapshot is required. The source tool checks the complete candidate hashes, inverses only the reviewed interface and offer substitution to frozen baseline hashes, guards all original validity writers and their priority/default, and extracts the actual candidate arm. Three mandatory negative mutations change an independent old valid writer, the new state clause and the core selection. Each must fail guards independently of the candidate hash check.

The proof uses a frozen independent original equation and the actual candidate expression. Its generated enum comes from the guarded actual source. The corpus contains **983,040 exact four-state core-grant comparisons**:

- 1,024 four-state five-bit states × 128 binary control forms × 4 selector values = 524,288 comparisons.
- 7 representative states × 16,384 four-state control forms × 4 selector values = 458,752 comparisons.

Known invalid states 30 and 31, unknown-state plus fault-0 default behavior, MMU, true EXEC offers and true TIMER offers have mandatory positive coverage. The shared arbitrary four-state fault input is a stronger superset of the unchanged actual result fault generator; it avoids duplicating an ISA fault decoder. The fixture proves the control product. Complete source inverse guards preserve every original fault, value and state writer.

Only the owned VVP file is deleted after success or failure. Compilation and runtime have 30-second and 90-second limits. Icarus remains optional, with no default-suite dependency.

This is a finite combinational control-product proof. Whole-special temporal equivalence, exact manual cycles and Fmax improvement require separate evidence. Full special/MMU/SPR/fault, simultaneous LSU/SRU arbitration, rename late/alias/owner, branch recovery and manual-cycle gates remain necessary before physical evaluation.

Fresh bounded proof (2026-10-16): the optional Make recipe passed 983,040 comparisons and all three negative source guards in a minimal checkout containing the exact candidate core/special and accepted package. Mandatory bins: 66,048 MMU; 6 true EXEC; 72 true TIMER; 638,976 unknown-state; 286,720 unknown-state/fault-0; 1,024 invalid-state comparisons. The full simulation Makefile and temporal benches have not run for this candidate.

The separate directed temporal test now passes at `35dc07c`: 1,099 full retirement packets with identical cycles and slots versus accepted `bfd023c`, including required EXEC/LSU overlap and SRU-priority collision. Physical timing remains unmeasured for this candidate.
