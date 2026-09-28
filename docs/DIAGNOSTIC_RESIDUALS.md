# Diagnostic residuals in the translated profile

This contract lists every source of a diagnostic halt (`halted_o` without
`checkstop_o`) in the MVP translated profile (`quartus/translated`, the
`ppc_core_bat_cached_bus60x` feature set with `ENABLE_FULL_DECODE`) and what
replaced it. Each former local restriction now follows the 603e manuals;
where the manuals leave a result undefined, the core makes one deterministic,
documented choice and never halts. Evidence:
[DIAGNOSTIC_RESIDUALS_FIRMWARE.md](DIAGNOSTIC_RESIDUALS_FIRMWARE.md).

Sources: *MPC603e & EC603e User's Manual* (UM) and *Programming Environments
Manual* Rev. 1 (PEM), per [references/SOURCES.md](references/SOURCES.md).

## Now architectural

| Case | Before | Now | Source |
| --- | --- | --- | --- |
| Any exception taken with MSR[TGPR]=1 (SC, program, FP unavailable, ISI, DSI, alignment, EXT, DEC, trace, IABR) | Rejected: diagnostic halt | Taken normally. Entry clears TGPR, so the handler runs on the normal r0-r3. SRR1 never holds TGPR (manual bit 14 is outside the saved subset). | UM Table 4-7 (printed 4-17): TGPR is 0 after every exception except the three TLB misses |
| TLB miss taken with MSR[TGPR]=1 | Diagnostic | Taken normally; entry sets TGPR again and overwrites SRR0/SRR1 and the miss registers | UM Table 4-7, Table 4-16 |
| `mtmsr` setting TGPR together with PR, EE, IR, DR, SE or BE | Diagnostic | Accepted. Such a mode ends at the next exception entry or `rfi`, both of which clear TGPR | UM Table 2-1 (printed 2-5), Table 4-7 |
| `mtspr SDR1` with IR or DR set | Diagnostic, SDR1 unchanged | Stored; later misses hash with the new value | PEM Table 2-22 notes (printed 2-42): undefined results. The 603e has no hardware table search and uses SDR1 only to form HASH1/HASH2 (UM 2.1.2.4, 5.5.2), so the write takes effect |
| `mfspr` DMISS, HASH1, HASH2, IMISS with IR or DR set | Diagnostic | Returns the register | UM 2.1.2 places no mode restriction on these supervisor SPRs |
| Page miss with a non-contiguous HTABMASK, an HTABORG not aligned to it, or nonzero reserved SDR1 bits | Miss ineligible: diagnostic | Miss taken; HASH1/HASH2 use the manual's bitwise formula, (HTABORG[7:15] OR (hash[0:8] AND HTABMASK)) | PEM 7.6.1.4.2: the PTEG address bits are "implemented as an OR function" of the masked hash |
| `tlbld`/`tlbli` with H=1, an API differing from rB, or nonzero RPA reserved or R bits | Diagnostic | Loaded. The entry takes V and VSID (the upper 25 compare bits) and EA[4:14] from rB; H, API, R and reserved bits are unused | UM 2.1.2.3 (printed 2-9/2-10): "the upper 25 bits of the DCMP or ICMP register and 11 bits of the effective address operand are loaded"; UM 2.1.2.5: R is ignored |
| `tlbld`/`tlbli` with IR or DR set | Diagnostic | Executed; the lane drains old traffic, commits and refetches | UM 2.3.8 (printed 2-48): execution with translation enabled is permitted with `sync` before and context synchronization after |
| `tlbld`/`tlbli` with compare V=0 | Diagnostic | The selected entry is left invalid. The core performs a `tlbie` of that congruence class, which also drops the other way and the same set of the other TLB; the extra loss costs only later misses | UM 2.1.2.3: V is among the loaded bits |
| `tlbld`/`tlbli` whose tag already sits in the other way | Diagnostic (duplicate rejection) | The load replaces it: the other way's matching entry is invalidated, so the latest load wins and a lookup never hits both ways | The manuals do not define duplicate TLB tags; this choice keeps lookups unambiguous |
| BAT write with nonzero reserved fields | Diagnostic, bank unchanged | Stored with reserved fields cleared (BATU mask `0xfffe1fff`, BATL `0xfffe007b`) | PEM Table 2-12 reserved fields; UM Table 4-7 note: reserved bits read as if written as zero |
| BAT write with a BL value outside PEM Table 7-10, or BEPI/BRPN bits under the BL mask | Diagnostic | Stored. BL acts bitwise: an EA bit leaves the compare where BL is one; BEPI is compared as written and BRPN is ORed with the offset | PEM 7.4.2 (only table values are valid; undefined otherwise) and PEM 2.1 BL description |
| IBAT write with W=1 | Diagnostic | Stored; fetches ignore W | PEM Table 2-12 note: W and G in IBATs give boundedly-undefined results. The 603e G check stays (UM Table 5-3) |
| Valid BAT entries whose effective ranges overlap | Diagnostic | The lowest-numbered matching entry translates | UM 5.3 implementation note (printed 5-20): multiple BAT hits are programming errors with unpredictable results; PEM 7.4.2 |

## Unreachable, asserted

These paths remain in the RTL for the reduced profiles, where a disabled
feature still ends in a diagnostic. In the translated profile each is
unreachable and a simulation assertion fires if one is ever taken.

| Path | Why unreachable | Assertion |
| --- | --- | --- |
| Untyped router fault: BAT response that is neither allow, clean page miss, ISI nor DSI; malformed segment snapshot; page response outside the typed set; `ROUTE_IFETCH_FATAL`; untyped data error to the core | BAT storage takes any value and translation reports one cause; the segment and TLB services return one cause per lookup; a TLB lookup never double-hits; with machine check every bus error is typed | `ppc_core_bat`: `untyped router fault reached the CPU` (when TLB misses, page data/instruction exceptions and machine check are all enabled) |
| TLB lookup hitting both ways (`invalid_input`) | Every load invalidates a matching entry in the other way | `ppc_tlb_service`: `TLB lookup hit both ways` |
| Page miss with stale capture provenance | Every context change drains and refetches, so a miss carries the committed IR/DR/PR | `ppc_special`: `fetch page miss lost its capture provenance`, `data page miss lost its capture provenance` |
| Exception state rejects a committed event (`S_EXCEPTION_HALT`) | Every remaining rejection (unknown kind, unaligned PC, ISI cause other than protection/guarded, disabled feature) is outside what the lane emits | `ppc_special`: existing unsupported-result assertion ([AUD-53](AUDIT.md)) |
| BAT, segment, TLB invalidate and TLB load response errors (privileged, unsupported, write rejected, refill rejected) | Problem-state forms become program exceptions before dispatch; BAT writes and TLB loads no longer reject | Covered by the router assertion above for translation, and by the unsupported-result assertion for MMU instructions |
| Fetch fault codes other than protection, guarded, page miss, machine check and IABR | The router emits no other code | Enumerated type; dispatch converts only the typed codes |
| Special-lane misaligned access; data fault codes `DATA_DSI_EXTERNAL` or 7 from the router | Dispatch turns every misaligned case into an alignment exception first; the router never emits those codes | None beyond the enumeration |

## Out of MVP scope

| Case | Behavior | Reason |
| --- | --- | --- |
| `mtmsr` or `rfi` setting MSR[LE] or MSR[ILE] | Diagnostic halt | The MVP is big-endian only; little-endian byte steering is not implemented |

A machine check with MSR[ME]=0 enters the architectural checkstop state
(`checkstop_o`), not a diagnostic.
