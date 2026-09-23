# DingusPPC reference audit

Date: 2026-09-12  
Scope: bounded, read-only audit of the checked-out `dingusppc/` tree for P01/P13 planning. The reference tree was not modified. Line numbers below refer to this checkout.

## Findings at a glance

| Area | Verified result | Adapter consequence |
|---|---|---|
| License | The top-level reference declares GNU GPL v3 (copyright 2018–26); `vcpkg.json` declares `GPL-3.0-or-later`. | Preserve applicable license and notice obligations when integrating or redistributing reference code. |
| Integer vectors | `ppcinttests.csv`: 5,620 executable rows. Field counts: 2,470 rows with 6 fields, 12 with 5, and 3,138 with 7. | Parser must accept the generated positional form and optional `rD/rA/rB/XER/CR` key-value fields. |
| Floating vectors | `ppcfloattests.csv`: 2,054 executable rows. Field counts: 1,390 with 8 fields, 24 with 6, and 640 with 9. | Parser must preserve raw FPR bit patterns, operand spellings (`snan`, `qnan`, `FLT_*`, `DBL_*`), rounding token, FPSCR, and CR. |
| Disassembly vectors | `ppcdisasmtest.csv`: 452 physical lines, 55 comments/empty lines, 397 executable rows. Data rows have 3–8 comma fields (22/44/108/200/21/2 by field count). | Skip blank/comment rows; first two fields are address and opcode, remaining fields reconstruct expected text with comma-space separators. |
| Build | PPC tests are optional (`DPPC_BUILD_PPC_TESTS=OFF`), and when enabled produce one `testppc` executable from all `cpu/ppc/test/*.cpp`; CSVs are copied beside it after build. | P13 needs a standalone runner or an explicit working-directory/data-file convention; do not assume CTest or a library target. |
| CPU variants | Enum includes MPC601, MPC603, MPC604, MPC603E (PID6, PVR `0x00060101`), MPC603EV (PID7v, PVR `0x00070101`), MPC750, MPC604E, MPC970MP. No MPC602 enum or 602-specific path was found. | Make the adapter model explicit; the intended PID7v baseline is `MPC603EV`, while `MPC603E` is the distinct PID6 option. Keep 602 disabled/experimental. |
| Endian | PPC LE and memory-controller LE are separate CMake options, both default OFF. Runtime LE state and MSR[LE]/MSR[ILE] handling are compiled conditionally. | A BE reference run is the reproducible baseline. LE comparison requires a build configured with the relevant options and separately encoded images. |
| MMU/TLB | The interpreter has a host-side two-level software TLB: 4,096-entry primary arrays and four-way secondary arrays for I/D paths, with BAT/PAT refill. | This is useful as a functional oracle for translation, not a cycle oracle or proof of 603e timing/resource geometry. |

## License and provenance

`dingusppc/LICENSE:1-3` identifies the GNU General Public License, version 3; `dingusppc/cpu/ppc/test/ppctests.cpp:1-19` repeats the GPL notice for the PPC test harness. `dingusppc/vcpkg.json:1-9` labels the project `GPL-3.0-or-later` and lists SDL2 as a package dependency. The repository's submodule declarations identify Cubeb and Capstone at `dingusppc/.gitmodules:1-7`; their source/license text is not present in this checkout (the submodule status is prefixed with `-`).

These facts establish what the files say. Any integration or redistribution of reference code must preserve applicable license and notice obligations; this audit does not determine derivative-work, linking, or compatibility questions.

## Test data and grammar

The source text files contain exactly 5,620 integer lines and 2,054 floating lines (`wc -l` on `dingusppc/cpu/ppc/test/ppcinttest.txt` and `ppcfloattest.txt`). `genppctests.py:361-408` converts each integer line into `MNEMONIC,opcode` followed by recognized `rD`, `rA`, `rB`/`rS`, `XER`, and `CR` fields; immediates and rotate parameters are consumed while generating the opcode. An unrecognized field emits `Unknown reg ID` and stops that output row (`:379-406`).

The integer harness skips blank/comment lines, requires at least five comma fields, parses opcode field 2 and the recognized key-value fields, initializes GPR3/GPR4 and XER/CR, then executes one opcode (`ppctests.cpp:89-169`). It compares GPR3 except for compare mnemonics, and compares XER and CR exactly (`:147-168`). This means the existing oracle does not encode a full architectural register file or exception/trace state.

`genppctests.py:410-452` defines the floating input grammar with one mnemonic, optional parenthesized rounding mode, up to four `frA`/`frB`/`frC`/`frD` values, and mandatory `FPSCR`/`CR` text. The harness accepts the same key-value output fields and maps `RTN`, `RTZ`, `RPI`, `RNI`, and `VEN` (`ppctests.cpp:196-280`). It converts ordinary operands through `stod`, while named NaN and float/double limit tokens have explicit handling (`:172-194`); a cosim parser should retain the original token and expected 64-bit destination to avoid host floating-point spelling/NaN ambiguity.

The disassembly reader skips blank/comment lines and rows with fewer than three fields, parses address/opcode as hexadecimal, and reconstructs expected text from field 3 onward (`testdisasm.cpp:33-89`). It compares the complete returned string for 397 rows (`:95-120`).

## Build configuration and actual environment check

The top-level CMake requires CMake 3.14 and C++20 (`dingusppc/CMakeLists.txt:1-7`). On non-Windows/non-Emscripten hosts it requires SDL2 (`:12-17`); the README additionally calls out recursive submodules and SDL2 development headers (`dingusppc/README.md:72-89`). The optional PPC test target links SDL2, Cubeb, and thread/dynamic-loader libraries (`CMakeLists.txt:245-265`), and copies all three CSVs next to the executable (`:292-300`).

An attempted isolated configure, `cmake -S dingusppc -B /tmp/dingusppc-audit-build -DDPPC_BUILD_PPC_TESTS=ON ...`, could not run because `cmake` is not installed in this environment (`/bin/bash: cmake: command not found`). `git -C dingusppc submodule status` reports both Capstone and Cubeb with a leading `-`, indicating uninitialized submodules. No build or test pass is claimed.

## Variants and endian behavior

The model identifiers and PVR values are defined at `ppcemu.h:131-141`: `MPC603E` is PID6 (`0x00060101`) and `MPC603EV` is PID7v (`0x00070101`). Machine call sites exercise MPC601, MPC603, MPC603E/603EV, MPC604/604E, MPC750, and MPC970MP (for example `machines/machinepippin.cpp:77`, `machinealchemy.cpp:107-108`, and `machinetnt.cpp:139-150`). `ppc_cpu_init` stores the requested PVR and derives `is_601` from the PVR family (`ppcexec.cpp:996-1006`), then selects power behavior for 603/603e/603ev/750 and 604/604e (`:1010-1027`). There is no `MPC602` enum member or corresponding initialization case in the audited source.

CMake options `DPPC_SUPPORT_PPC_LE` and `DPPC_SUPPORT_MEM_LE` default OFF and define separate compile-time switches (`CMakeLists.txt:87-98`). The architectural state has conditional `is_LE` storage (`ppcemu.h:75-88`), and MSR comments distinguish LE as unavailable on 601 and ILE as unavailable on 601 (`:257-290`). Exception entry copies ILE to LE only for non-601 and calls the endian transition hook (`ppcexceptions.cpp:116-125`).

There is a concrete coverage gap to carry into P26: the page-table address munging blocks are disabled with `#if 0 && SUPPORTS_PPC_LITTLE_ENDIAN_MODE` at `ppcmmu.cpp:206-209` and `:313-321`, even though normal virtual-memory read paths apply LE address munging at `:1167-1202`. Therefore “LE option exists” is not evidence that all page-table/MMU behavior is validated.

## Software TLB and oracle limits

The reference implements host-side cached translation, not a synthesizable architectural TLB: constants define a 4,096-entry primary and four-way secondary (`ppcmmu.cpp:462-475`), while separate I/D arrays and current pointers are allocated at `:585-607`. Instruction refill chooses 601 block translation versus non-601 IBAT, then page translation, and fills the secondary cache (`:734-782`); data refill similarly chooses 601/non-601 DBAT or page translation and tracks permissions/C-bit state (`:790-842`). `tlbie` is implemented, but `tlbia`, `tlbld`, `tlbli`, and `tlbsync` contain placeholders/logging (`ppcopcodes.cpp:2122-2170`), including the explicit “tlbia needs to be implemented” message (`:2140-2147`).

Consequently the reference can provide useful state-level checks for selected BAT/PAT/TLB accesses, permissions, endian lane behavior, and C-bit updates. It cannot certify 603e TLB geometry, software-loaded TLB instruction behavior, cycle timing, bus protocol, speculative ordering, or precise RTL exceptions. The existing interpreter also aborts on unsupported direct-store segments and instruction fetch from MMIO (`ppcmmu.cpp:278-289`, `:767-784`), which an adapter must classify as oracle gaps rather than treat as architectural pass/fail results.

## Smallest P13 follow-up adapter tasks

1. Add a license/provenance manifest that records the GPLv3 reference, absent submodule checkouts, selected PVR, source commit, and required license/notice preservation.
2. Add a parser-only executable or library for the three CSV grammars, with row counts and malformed-row diagnostics matching the harness rules above. Keep raw floating tokens and expected bit patterns.
3. Add an isolated reference runner that resets state, executes one encoded instruction/program, and emits a versioned architectural snapshot (GPRs, CR, XER, FPSCR, FPR bits, selected SPRs, PC, exception outcome). Do not compare cycle counts.
4. Add explicit model gating: default `MPC603EV` (PID7v), optional `MPC603E` (PID6) and other enumerated models, and an early error for MPC602/unknown PVR. Record `include_601` separately because it changes opcode behavior without changing the PVR (`ppcexec.cpp:1004-1006`).
5. Add BE smoke coverage first; make LE a separately configured lane with independent encoded images and mark MMU page-table LE cases pending until the `#if 0` paths are resolved by P26.
6. Add oracle-gap dispositions for the four placeholder TLB operations, unsupported direct-store/MMIO cases, undefined floating behavior, and any exception path that only powers off or aborts. These should produce “unsupported/indeterminate” artifacts rather than false architectural mismatches.
