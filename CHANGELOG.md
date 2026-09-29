<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Changelog

Accepted MVP rounds, oldest first. Evidence and scores are in the
[round ledger](docs/plans/current/MVP_EXECUTION_PLAN.md) and
[scorecard](docs/SYSTEM_COMPLETION.md). Release scope: [RELEASE.md](docs/RELEASE.md).

## Unreleased: MVP

### Up to 2026-09-22

- Wave 1: executable integration baseline (build, core wrapper, bus composition).
- Instruction cache moved to a synchronous block-RAM data array.
- Wave 2: precise alignment exceptions (bounded policy).
- Wave 3: typed protection and guarded fetch faults.
- Wave 4: live MSR/SRR context, external interrupts, TB64 and DEC32.
- Bounded recovery policy and the persistent system scorecard.
- Explicit XER SPR access for state saving.
- Event-entry reset verification for EXT/DEC.
- CPU-owned runtime BAT reads and writes.
- Resumable BAT protection DSI.
- CPU segment registers (`mfsr`/`mfsrin`/`mtsr`/`mtsrin`).
- Page translation through prefilled I/D TLBs.
- `tlbie` committed at retirement.

### 2026-09-23

- TLB refill shares the invalidate reservation.
- DCMP, ICMP and RPA software seed registers.
- `tlbld`/`tlbli` from captured software state.
- Precise page-protection DSI.
- Page ISI for PP, G and no-execute segment faults.
- Page-miss records reach precise retirement.
- CPU-owned SDR1.
- TGPR bank for miss handlers.
- Instruction, data-load and data-store TLB-miss vectors.
- Matched TLB way retained for changed-bit stores.
- Full IMISS/DMISS capture; software PTEG search with R/C writeback.
- Software PP/key checks; failed searches become ISI/DSI.
- Translated core over scalar 60x.
- Search and fault firmware entirely over 60x pins.
- Translated ARTRY/DRTRY and TEA handling.
- Physical instruction cache behind translation.
- Search and fault firmware through the instruction cache.
- Instruction-cache remap, stale-code and maintenance gates.
- Interrupts during held cache refill.
- DEC during held cache refill.

### 2026-09-27

- Integrated timing closure (AUD-01, AUD-16).
- Registered RS result bypass (AUD-21).
- Direct-store segment faults and `tlbsync` decode.
- Cache maintenance instructions and held-refill `icbi`.
- Seeded bus retries across the translated MMU stress.
- Byte-reverse, multiple/string, reservation and misaligned accesses.

### 2026-09-28

- Machine check, single-step and branch trace, IABR.
- Interface timing contract implemented in the measurement SDCs.
- Full decode: no instruction word halts.
- Scope change: data cache, chip package and timed multiplier join the MVP.
- Standalone 16-KiB four-way write-back data cache.
- Iterative DSP multiplier with 603e cycle counts.
- `ppc603e` pin-level package top.
- Diagnostic halts replaced with manual behavior.
- Registered fetch-to-decode stage; all tops meet 66 MHz.
- Chip firmware enables the instruction cache at boot.
- Data cache serves the LSU.
- Data cache on the BIU with 60x snooping, enabled in the chip and translated tops.
