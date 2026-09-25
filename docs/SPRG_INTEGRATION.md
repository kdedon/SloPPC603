# Bounded SPRG0–SPRG3 integration

`ppc_core` implements exact `mfspr` and `mtspr` aliases for SPRG0 through SPRG3 when `ENABLE_SUPERVISOR_EXCEPTIONS=1`. The parameter defaults to zero. The default 168-form profile therefore continues to reject these selectors; the enabled supervisor profile adds eight forms.

| Form | SPR | Mask / value | Architectural effect |
|---|---:|---:|---|
| `mfsprg0 rD` | 272 | `0xfc1fffff / 0x7c1042a6` | `rD ← SPRG0` |
| `mtsprg0 rS` | 272 | `0xfc1fffff / 0x7c1043a6` | `SPRG0 ← rS` |
| `mfsprg1 rD` | 273 | `0xfc1fffff / 0x7c1142a6` | `rD ← SPRG1` |
| `mtsprg1 rS` | 273 | `0xfc1fffff / 0x7c1143a6` | `SPRG1 ← rS` |
| `mfsprg2 rD` | 274 | `0xfc1fffff / 0x7c1242a6` | `rD ← SPRG2` |
| `mtsprg2 rS` | 274 | `0xfc1fffff / 0x7c1243a6` | `SPRG2 ← rS` |
| `mfsprg3 rD` | 275 | `0xfc1fffff / 0x7c1342a6` | `rD ← SPRG3` |
| `mtsprg3 rS` | 275 | `0xfc1fffff / 0x7c1343a6` | `SPRG3 ← rS` |

The manual numbers instruction bits from the most significant bit. The XFX SPR field is split in the instruction word; the RTL reconstructs the ordinary SPR number as `{insn[15:11], insn[20:16]}`. Thus SPR272 has encoded halves 16 and 8. The table records complete instruction words with the variable GPR field cleared; mask `0xfc1fffff` leaves only that GPR field variable and fixes Rc to zero.

## Sources

The processor source is *MPC603e & EC603e RISC Microprocessors User's Manual* (1997), local file `../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, SHA-256 `6bad9fb8a3a13792f93a8593d795e0b03d3ab0349846c62fe28008a1b22e63c7`.

- Table 4-8, PDF 177 / printed 4-19, gives `00000000` for the SPRGs after hard reset.
- Section 4.5.1.2 and Table 4-9, PDF 178 / printed 4-20, describe soft reset separately and do not reinitialize the SPRGs.
- Appendix A Table A-1, PDF 365, supplies the generic `mfspr` and `mtspr` rows. Table A-26, PDF 385, supplies the XFX field layout and extended opcodes.

The architectural source is *PowerPC Microprocessor Family: The Programming Environments, Rev. 1*, local file `../MPCFPE.pdf`, SHA-256 `0600de0a3cb81636b9d511aa6b185e2fccc02f895ce4630411725634ef8e7eee`.

- Section 2.3.8 and Figure 2-26, PDF 95 / printed 2-33, define SPRG0–SPRG3 as complete 32-bit registers on a 32-bit implementation and describe their operating-system storage role.
- Table 8-10, PDF 568 / printed 8-156, assigns SPR272–275 to supervisor `mfspr` access.
- Table 8-15, PDF 585 / printed 8-173, assigns the same selectors to supervisor `mtspr` access.

These sources define ordinary full-width storage. No source says a write preserves any part of the selected register, so `mtspr` replaces all 32 bits.

## Execution and privilege contract

The existing special lane captures the GPR value, reconstructed SPR selector, and exact completion producer at dispatch. It admits a special operation only after the completion queue and normal execution path have drained, then blocks younger dispatch through accepted retirement.

`mfsprg*` returns a captured SPRG value through the normal tagged GPR result. `mtsprg*` changes one `sprg_q` element only in `S_HOLD` when `commit_match` is true. A canceled or stale producer cannot write. A stalled finished packet leaves the bank unchanged until retirement. Register aliases do not add dependencies beyond the single source or destination named by the form. CR, XER, LR, CTR, MSR, SRR0, SRR1, memory, and the other three SPRGs are preserved.

Problem-state execution is normalized before allocation into the existing selected privileged-instruction program event. That rewrite clears every GPR and state-write permission from the original operation. It therefore cannot expose an SPRG value through a destination or change an SPRG before the program-event retirement and redirect.

The core reset input models the relevant hard-reset state for this bank and clears all four registers to the Table 4-8 value. There is no separate soft-reset input, so the Table 4-9 soft-reset preservation behavior is outside this interface. This is distinct from claiming that every physical reset source clears SPRG state.

## Verification boundary

The metadata validator checks all eight swapped-selector encodings, source/destination effects, supervisor privilege, opt-in feature tag, selector list, and primary source locators. Negative tests reject selector/effect/source drift. Strict Verilator lint covers both the default and enabled `ppc_core` configurations.

The independent decoder checks cover default rejection, enabled supervisor access, exact and neighboring selectors, fixed Rc, GPR variation, and permission normalization. The actual-core checks cover full-width round trips, bank independence, stalled retirement, pre-finish cancellation and recovery, problem-state sanitization without read or write leakage, exact saved privilege state, and hard reset. Metadata labels the eight forms `accepted_sprg_integration_benches` only after both gates passed.

Run from the repository root:

```sh
verilator --lint-only -Wall --top-module ppc_core $(sed 's#^../##' rtl/files.f)
verilator --lint-only -Wall --top-module ppc_core "-GENABLE_SUPERVISOR_EXCEPTIONS=1'b1" $(sed 's#^../##' rtl/files.f)
python3 sim/tools/isa_generate.py --check
python3 sim/tools/test_isa.py
make -C sim test-sprg-decode
make -C sim test-core-sprg
```

Validated with Verilator 5.020: strict default/enabled core lint passed, `tb_sprg_decode` passed 8,097 checks, `tb_core_sprg` passed 192 checks, and 37 ISA metadata tests passed. The generated metadata reports 186 reviewed entries: 168 default implemented, 15 supervisor opt-in, and three serialization opt-in.

## Remaining scope

This milestone does not add user access, additional SPR selectors, `mfspr`/`mtspr` wildcard decoding, time-base, decrementer, PVR, HID, MMU, cache, debug, performance-monitor, or implementation-specific SPR behavior. It does not provide a software soft-reset entry or claim 603e SRU cycle timing. The enabled profile remains a serialized functional model rather than full supervisor or P14 completion.
