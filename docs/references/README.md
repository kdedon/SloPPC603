# CPU references

Distilled, source-backed material used by this CPU project:

- [Source audit and precedence](SOURCES.md) identifies the manuals, page maps and model limits.
- [ISA matrix](ISA_MATRIX.md) is generated from the project's instruction metadata.
- [Timing contract](TIMING_SPEC.md) transcribes accepted 603e timing rules.
- [Source reconciliation](SOURCE_RECONCILIATION.md) records the 2026-10-05 check of these contracts against the manuals.
- [Manual inventory](MANUAL_INVENTORY.md) lists what the manuals define and whether the design has it.
- [Bus contract](BUS_SPEC.md), [encodings](BUS_ENCODINGS.md) and [addressing](BUS_ADDRESSING.md) record reviewed 60x interface details.

The external PDF manuals stay outside this repository. File names and page
references in these documents identify local source copies; they are not
vendored or committed here. The [current plan](../plans/current/PLAN.md) states
what remains to implement and verify.
