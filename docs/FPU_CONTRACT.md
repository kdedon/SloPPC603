# MPC603e floating-point contract

This contract targets the MPC603e/PID7v FPU. `UM` means the *MPC603e & EC603e User's Manual* (`1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`); `PEM` means *The Programming Environments Manual*, Rev. 1 (`MPCFPE.pdf`). Citations give section or table and **one-based physical PDF page**. UM-specific behavior takes precedence over generic architecture behavior; contradictions remain explicit below. EC603e and 602 are outside this contract. The F1 arithmetic experiment exposes raw results and metadata; the full standalone FPU must own its FPR/FPSCR shell and provide tagged instruction/result, kill, backpressure, memory-request, CR-update, and exception outputs for later core attachment. The core still owns MSR, final CR, LSU transport, and retirement. [UM §§1.1.4.2, 2.2.1, 4.5.7–8, PDF 50–51, 90, 187–189; PEM §§2.1.3–4, 3.3, PDF 68–72, 123–150]

## State and accepted instructions

There are 32 architectural 64-bit FPRs. Floating data in an FPR use binary64 encoding; single-precision loads and results are **converted to binary64 numeric values**, not stored as a binary32 word in either half. Double loads/stores and bit moves preserve all 64 bits. `fctiw`/`fctiwz` place the integer word in FPR bits 32–63; bits 0–31 are undefined. `mffs` places FPSCR in FPR bits 32–63, leaving bits 0–31 undefined. `stfiwx` stores the low word without numeric conversion; its stored value is undefined if derived from `lfs`, single-result arithmetic, or `frsp`, even through FP moves. Raw FPR bits, including NaN payloads and signed zero, must travel intact where the instruction specifies a bit move. [UM §§2.1.2.1, 2.2.1, 2.3.4.2.3, 2.3.4.3.9–10, PDF 86, 90–91, 105, 112–113; PEM §§3.3.1, 3.3.4, PDF 122–123, 130–131; PEM `fctiwx`, `fctiwzx`, `mffsx`, `stfiwx`, PDF 492–493, 565, 646 / 8-80–8-81, 8-153, 8-234]

| Class | Implemented 603e instructions (optional `.` means Rc=1) | Source |
| --- | --- | --- |
| Arithmetic | `fadd[s][.]`, `fsub[s][.]`, `fmul[s][.]`, `fdiv[s][.]`, `fres[.]`, `frsqrte[.]`, `fsel[.]` | UM Table 2-14, PDF 104 / 2-26 |
| Fused multiply-add | `fmadd[s][.]`, `fmsub[s][.]`, `fnmadd[s][.]`, `fnmsub[s][.]` | UM §2.3.4.2.2, Table 2-15, PDF 104 / 2-26 |
| Round/convert | `frsp[.]`, `fctiw[.]`, `fctiwz[.]` | UM Table 2-16, PDF 105 / 2-27 |
| Compare | `fcmpu`, `fcmpo` | UM Table 2-17, PDF 105 / 2-27 |
| FPSCR | `mffs[.]`, `mcrfs`, `mtfsfi[.]`, `mtfsf[.]`, `mtfsb0[.]`, `mtfsb1[.]` | UM Table 2-18, PDF 106 / 2-28 |
| Bit moves | `fmr[.]`, `fneg[.]`, `fabs[.]`, `fnabs[.]` | UM Table 2-19, PDF 106 / 2-28 |
| Load/store | `lfs[x/u/ux]`, `lfd[x/u/ux]`, `stfs[x/u/ux]`, `stfd[x/u/ux]`, `stfiwx` (expand the four address forms individually; `stfiwx` is indexed only) | UM Tables 2-25–26, PDF 112–113 / 2-34–2-35 |

The decoder must use the primary/XO pair, including reserved-field checks on the individual instruction page. The FPU primary/XO pairs are: primary `59`: `fdivs 18`, `fsubs 20`, `fadds 21`, `fres 24`, `fmuls 25`, `fmsubs 28`, `fmadds 29`, `fnmsubs 30`, `fnmadds 31`; primary `63`: `fcmpu 0`, `frsp 12`, `fctiw 14`, `fctiwz 15`, `fdiv 18`, `fsub 20`, `fadd 21`, `fsel 23`, `fmul 25`, `frsqrte 26`, `fmsub 28`, `fmadd 29`, `fnmsub 30`, `fnmadd 31`, `fcmpo 32`, `mtfsb1 38`, `fneg 40`, `mcrfs 64`, `mtfsb0 70`, `fmr 72`, `mtfsfi 134`, `fnabs 136`, `fabs 264`, `mffs 583`, `mtfsf 711`. FP indexed memory uses primary `31` with XO `lfsx 535`, `lfsux 567`, `lfdx 599`, `lfdux 631`, `stfsx 663`, `stfsux 695`, `stfdx 727`, `stfdux 759`, `stfiwx 983`. FP D-form memory primaries are `lfs 48`, `lfsu 49`, `lfd 50`, `lfdu 51`, `stfs 52`, `stfsu 53`, `stfd 54`, `stfdu 55`. [UM Tables 6-5–6, PDF 272–275 / 6-26–6-29]

`fsqrt` and `fsqrts` are not implemented: decode must produce illegal-instruction program exceptions, not route them through a donor square-root datapath. `frsqrte` is an implemented estimate. The 603e list also excludes 64-bit-only conversion instructions. [UM Table B-1, PDF 407 / B-1; §4.5.7.2, PDF 188 / 4-30; Table 6-5, PDF 273 / 6-27]

An FPSCR instruction synchronizes earlier FP effects and prevents later FP instructions from appearing to initiate until it completes. A move instruction changes FPR sign/data bits but does not update FPSCR. Rc copies the final FPSCR[0:3] to CR1 even for moves and FPSCR instructions with Rc; compare writes the chosen CR field and FPSCR[FPCC]. `+0` and `-0` compare equal. Both compares report unordered for any NaN. `fcmpu` sets VXSNAN only for SNaN; `fcmpo` sets VXVC for QNaN and sets VXSNAN for SNaN, additionally setting VXVC for that SNaN when VE=0. [UM §§2.3.4.2.4–6, PDF 105–106 / 2-27–2-28; PEM §§2.1.3.2–3, 4.2.2.4, PDF 68–69, 181; PEM `fcmpox`, `fcmpux`, PDF 488–489 / 8-76–8-77]

## Number representation and rounding

`RN` selects nearest, ties to even (`00`), toward zero (`01`), toward +∞ (`10`), or toward −∞ (`11`). General arithmetic, `frsp`, and conversion calculate an infinitely precise, unbounded intermediate value before one destination-format rounding. `fctiwz` overrides RN with toward-zero. Single-result basic and fused arithmetic accepts only operands exactly representable as binary32, rounds **directly** to binary32, then widens exactly to binary64 for the FPR. The `fres` instruction takes a floating-point `frB` operand without that source-precision precondition. Supplying a non-binary32 operand to a single-result arithmetic instruction makes result/status undefined. Double-result arithmetic accepts binary32 or binary64 operands and produces binary64. A binary64 intermediate rounded before binary32 can double-round; it is not a conforming implementation of the direct binary32 result. [UM §2.2.1 and §§2.3.4.2.1–3, PDF 90–91, 103–105; PEM §§3.3.4–5, Table 3-8, PDF 130–133; PEM `fresx`, PDF 509–510 / 8-97–8-98]

The fused family multiplies and adds/subtracts before rounding; the 106-bit product fraction participates in the addition. `fnmadd`/`fnmsub` first round the fused magnitude under RN and **then** negate the final finite, infinity, or zero result. NaN signs are never algebraically negated: generated QNaN is positive and propagated NaN payload/sign follow the usual selection rule. Reversing sign before directed rounding produces the wrong result. A rounded `fmul` fed to `fadd` also cannot implement FMA, especially under cancellation. [UM §2.3.4.2.2, PDF 104 / 2-26; PEM §4.2.2.2, PDF 178–179 / 4-28–4-29; PEM `fnmaddx`, `fnmaddsx`, `fnmsubx`, `fnmsubsx`, PDF 505–508 / 8-93–8-96]

IEEE mode (`NI=0`) preserves denormal operands and gradual-underflow results. A tiny intermediate is denormalized and rounded; underflow is tested before rounding, whereas overflow is tested after rounding. Exact cancellation produces +0 except under round-toward-−∞, which produces −0; multiply/divide signs are operand-sign XOR. The 603e `NI=1` selects its nondenormalized mode: a result that would be denormal is replaced by a zero of the same sign. NI does **not** authorize indiscriminate flushing of input operands. The current standalone implementation retains IEEE-derived status/enables while replacing the delivered denormal result with signed zero; that is an explicit project policy and does not establish full 603e NI conformance. [PEM §§3.3.1.5, 3.3.2–3, 3.3.5–6, PDF 126–129, 132–141; UM §2.3.4.2, PDF 103 / 2-25; PEM Table 2-4, PDF 72 / 2-10]

`lfs` converts binary32 to binary64 without FP exceptions. `stfs` converts to binary32, denormalizing if needed, without FP exception detection; software must use `frsp` first when it needs rounding/status for a binary64 value. `lfd`/`stfd` move binary64 bits. Each FP memory operand must be at least word aligned on the 603e; a word-aligned 64-bit access is allowed but slower. An unaligned FP access takes an alignment exception before partial architectural update. Address-update forms commit both destination/base together on success. [PEM §3.3.4, PDF 130–131; UM §§2.2.3–4, 2.3.4.3.8–10, 4.5.6, PDF 91–92, 112–113, 184–186]

## NaNs, invalid causes, and estimates

Exponent all ones and nonzero fraction is a NaN; fraction bit 0 (architectural bit numbering) distinguishes signaling (`0`) from quiet (`1`). An arithmetic SNaN signals `VXSNAN`; when invalid is disabled it is quieted for the result. Quiet NaN payload selection follows `frA`, then `frB`, then `frC`; `frsp` clears the low 29 fraction bits of its `frB` payload. A generated invalid-result QNaN is positive `0x7ff8000000000000`. NaN sign is a payload bit, not an algebraic sign. QNaN and SNaN compare behavior differs for ordered/unordered compare and must be checked per instruction. [PEM §3.3.1.7, Figures 3-16–17, PDF 127–128; §§3.3.6.1.1, 4.2.2.4, PDF 140–141, 190–191]

`fsel` copies `frC` when `frA ≥ 0`, otherwise `frB`; both signs of zero select `frC`, while a NaN selector selects `frB`. It is a bit selection, does not update FPSCR, and can copy an SNaN unchanged. Rc still copies prior FPSCR[0:3] to CR1. [PEM `fselx`, PDF 514 / 8-102]

`fres` returns a single-precision reciprocal estimate with relative error at most 1/256 for finite nonzero input. Its result may vary between executions. Inputs `−∞, −0, +0, +∞` produce `−0, −∞, +∞, +0` respectively; zero signals ZX and suppresses the result when ZE=1. SNaN yields a quiet NaN and VXSNAN, suppressing the result when VE=1; QNaN propagates without exception. FPRF describes a delivered result, except when suppressed; FR and FI are undefined for ordinary estimates; invalid and zero-divide paths clear them under the exception tables below. XX is unchanged. Overflow/underflow handling applies where the reciprocal cannot be delivered as an ordinary finite binary32 estimate. The 603e table gives 18 cycles. [PEM `fresx`, PDF 509–510 / 8-97–8-98; UM Table 6-5, PDF 272 / 6-26]

`frsqrte` returns a reciprocal-square-root estimate in an FPR with relative error at most 1/32 for positive finite input; the result may vary between executions. Inputs `−∞` and negative nonzero yield QNaN and VXSQRT (suppressed with VE=1); `−0, +0, +∞` yield `−∞, +∞, +0` (the zero cases signal ZX and suppress with ZE=1). SNaN yields QNaN/VXSNAN (suppressed with VE=1); QNaN propagates without exception. FPRF describes a delivered result, except when suppressed; FR and FI are undefined for ordinary estimates; invalid and zero-divide paths clear them under the exception tables below. OX/UX/XX are unchanged. Although the instruction names a double-precision estimate, PEM requires source and result to be representable in single precision. The standalone engine therefore delivers at most 24 significand bits; full-range binary64 source handling is a tested extension, not part of that guaranteed domain. The 603e table gives `1-1-1` cycles. No fixed 603e estimate bit pattern is promised by these sources. [PEM `frsqrtex`, PDF 512–513 / 8-100–8-101; UM Table 6-5, PDF 273 / 6-27]

## FPSCR bit contract

Bit numbers below are architectural, most significant bit first. Exception bits are sticky, except summary bits `FEX`/`VX`; FPSCR writes/clears use the specified field or bit masks. `FX` sets when an instruction changes an exception bit from zero to one, with the documented `mtfsf`/`mtfsfi` exception; it is itself sticky. `VX` is OR of invalid causes; `FEX` is OR of each sticky summary condition gated by its enable. `XX` accumulates `FI` for instructions that update FI. Reserved bit 20 is not a usable status bit. [PEM §2.1.4, Figure 2-5, Tables 2-4–5, PDF 69–72; §3.3.6, Table 3-9, PDF 134–136]

| Bit(s) | Field | Required meaning | Source |
| --- | --- | --- | --- |
| 0 | FX | Sticky exception-change summary. | PEM Table 2-4, PDF 70 |
| 1 | FEX | `(VX&VE)∨(OX&OE)∨(UX&UE)∨(ZX&ZE)∨(XX&XE)`; recomputed, not sticky. | PEM Table 2-4, PDF 70 |
| 2 | VX | OR of bits 7–12 and 21–23; recomputed, not sticky. | PEM Table 2-4, PDF 70–71 |
| 3–6 | OX, UX, ZX, XX | Sticky overflow, underflow, zero-divide, inexact; XX is sticky FI. | PEM Table 2-4, PDF 70 |
| 7–12 | VXSNAN, VXISI, VXIDI, VXZDZ, VXIMZ, VXVC | Sticky SNaN, ∞−∞, ∞/∞, 0/0, ∞×0, invalid compare. | PEM Table 2-4, PDF 70–71 |
| 13–14 | FR, FI | Last arithmetic/conversion fraction increment and inexact/disabled overflow; not sticky. `fres`/`frsqrte` make both undefined. | PEM §§2.1.4, 3.3.5, PDF 71, 133–134 |
| 15–19 | FPRF | `C,FL,FG,FE,FU`: result class/condition or one-hot compare outcome; not sticky. See class encodings below. | PEM Tables 2-4–5, PDF 71–72 |
| 20 | — | Reserved. | PEM Figure 2-5/Table 2-4, PDF 70–71 |
| 21–23 | VXSOFT, VXSQRT, VXCVI | Sticky software invalid request, invalid square-root or reciprocal-square-root estimate, invalid integer convert. VXSOFT is set only by explicit FPSCR manipulation; `frsqrte` can set VXSQRT although `fsqrt` is unsupported. | PEM Table 2-4, PDF 71; PEM `frsqrtex`, PDF 512–513; UM Table B-1, PDF 407 |
| 24–28 | VE, OE, UE, ZE, XE | Invalid, overflow, underflow, zero-divide, inexact enables. | PEM Table 2-4, PDF 71 |
| 29 | NI | Implementation-specific non-IEEE mode; 603e denormal-result flush as above. | PEM Table 2-4, PDF 72; UM §2.3.4.2, PDF 103 |
| 30–31 | RN | `00` nearest-even, `01` zero, `10` +∞, `11` −∞. | PEM Tables 2-4, 3-8, PDF 72, 132 |

`FPRF[15:19]` class encodings, in order `C,FL,FG,FE,FU`: QNaN `10001`; −∞ `01001`; negative normal `01000`; negative denormal `11000`; −0 `10010`; +0 `00010`; positive denormal `10100`; positive normal `00100`; +∞ `00101`. Compare writes one-hot `FL/FG/FE/FU` in bits 16–19. An undefined result may make FPRF undefined. [PEM Tables 2-4–5, PDF 71–72]

For a single-precision result, FPRF classifies the **single** result before its exact widening to the FPR's binary64 encoding. Thus `frsp(2^-149)` stores binary64 `0x36a0000000000000` while FPRF is positive denormal `10100`, even though that binary64 encoding is normal. [PEM §D.4.1, PDF 758 / D-10; §3.3.4, PDF 130–131]

`mcrfs` copies one FPSCR nibble into the selected CR field, then clears exception bits in the source nibble except FEX and VX. `mtfsf` copies selected 4-bit fields from FPR bits 32–63; `mtfsfi` writes one immediate nibble; `mtfsb0/1` clear/set one bit. FEX and VX are always recomputed rather than explicitly written. `mtfsf`/`mtfsfi` set FX from their operand only when field 0 is selected, even when OX changes 0→1; `mtfsb1` can also affect FX. A record-form FPSCR instruction copies CR1 **after** its own FPSCR change. [PEM `mcrfs`, `mtfsb0x`, `mtfsb1x`, `mtfsfx`, `mtfsfix`, PDF 562, 577–580 / 8-150, 8-165–8-168; PEM Table 2-4, PDF 70–71]

`fctiw` applies RN; `fctiwz` always rounds toward zero. Range is checked **after** integer rounding, so a fractional value above the maximum integer can round to that maximum without VXCVI. Out-of-range positive or +∞ saturates to `0x7fffffff` when invalid is disabled; out-of-range negative, −∞, or NaN produces `0x80000000`. Invalid conversion sets VXCVI, and an SNaN can also set VXSNAN; FR/FI clear. With VE=1, destination and FPRF remain unchanged; with VE=0, destination receives the saturation value and FPRF is undefined. For valid conversions FR records whether rounding incremented the word and FI records discarded precision. [PEM `fctiwx`, `fctiwzx`, PDF 492–493 / 8-80–8-81; §D.4.2, PDF 761–763 / D-13–D-15]

Invalid causes must be distinguished at the arithmetic interface: SNaN, infinity subtraction, infinity division, zero division by zero, infinity multiplication by zero, invalid comparison, and out-of-range/NaN integer conversion. Overflow, underflow, zero-divide, and inexact must remain separate. Enabling one condition affects exception/result handling, so a five-flag donor interface alone cannot update FPSCR. [PEM §§3.3.6.1–2, Tables 2-4, 3-9, PDF 70–71, 134–143]

PEM's result/status tables specify the base behavior: invalid always sets its cause bit(s); VE=0 delivers a QNaN for arithmetic/`frsp` or a saturated integer word for invalid conversion, and VE=1 leaves frD unchanged, with FR/FI cleared. The arithmetic/`frsp` instruction pages set FPRF for a delivered QNaN and leave it unchanged under VE=1; Table 3-12's FPRF row appears reversed, as logged below. Invalid compare writes unordered to CR/FPCC and leaves FR/FI and FPRF[C] unchanged. A finite nonzero dividend divided by zero, or a zero operand to either estimate, sets ZX and clears FR/FI; ZE=0 delivers signed infinity and FPRF, while ZE=1 leaves frD/FPRF unchanged. [PEM §§3.3.6.1.1–2, Tables 3-12–13, PDF 143–145 / 3-37–3-39; PEM `frspx`, PDF 511 / 8-99]

Overflow always sets OX. OE=0 produces infinity or max finite according to sign and RN, sets FI and XX, leaves FR undefined; OE=1 stores an exponent-adjusted rounded result (double exponent −1536, single exponent −192) and reports FR/FI of that rounding. For a tiny nonzero intermediate, UE=1 sets UX and stores an exponent-adjusted rounded result (double exponent +1536, single +192); UE=0 denormalizes and rounds, setting UX only if that result is inexact. Inexact sets XX and stores the rounded result whether XE is set or clear; XE=1 also makes FEX true. These architectural status/result tables must be checked against the UM exception conflict below before core retirement behavior is frozen. [PEM §§3.3.6.2.1–3, Tables 3-14–16, PDF 147–150 / 3-41–3-44]

## Exception and retirement boundary

`MSR[FP]=0` causes FP-unavailable at vector `0x00800` for FP arithmetic, move, load, and store before they perform an architectural effect. The architecture's `MSR[FE0:FE1]` settings are `00` ignore FP program exceptions, `01` imprecise nonrecoverable, `10` imprecise recoverable, and `11` precise. The 603e treats both unequal-bit modes as precise. The operative exception route for this contract is the UM Table 4-1 formula `(FE0∨FE1)&FPSCR[FEX]` to program vector `0x00700`; PEM Tables 3-12–16 govern result/status under enabled conditions. A conflicting UM paragraph is logged below as a silicon-revision risk. FPSCR, FPR, CR and store effects must be owned by the same completed instruction to avoid committing killed work. [UM Table 4-1, PDF 163 / 4-5; §§4.5.7.1, 4.5.8, PDF 188–189 / 4-30–4-31; PEM §3.3.6, Tables 3-11–16, PDF 140–150 / 3-34–3-44]

## Semantics gaps and source conflicts

| Subject | Required boundary / evidence | Standalone disposition / remaining evidence |
| --- | --- | --- |
| Enabled-exception paragraph | UM §4.5.7.1 (PDF 188 / 4-30) says emulation trap regardless of MSR FE and **no FPSCR/FPR update**. UM Table 4-1 (PDF 163 / 4-5) instead gives program vector `0x00700` and requires `(FE0∨FE1)&FPSCR[FEX]`; PEM Tables 3-12–16 (PDF 144–150) require cause/status updates and specify destination handling. This contract uses the mutually consistent Table 4-1/PEM behavior. | Keep the divergent paragraph visible; look for mask-specific errata or silicon evidence before claiming cycle-exact exception behavior. Directed enabled/disabled tests must encode the selected Table 4-1/PEM rule. |
| Invalid-result FPRF table | PEM Table 3-12 (PDF 144 / 3-38) prints VE=1 “set for QNaN,” VE=0 “unchanged.” The `frspx` instruction (PDF 511 / 8-99) and §D.4.1 (PDF 760 / D-12) set FPRF for a delivered QNaN and leave it unchanged under VE=1. §D.4.2 (PDF 761–763 / D-13–D-15) likewise leaves conversion FPRF unchanged under VE=1. This contract uses the explicit instruction/algorithm rules. | Retain VE=0/1 directed tests and seek an erratum before claiming the printed Table 3-12 row reflects silicon. |
| Double-precision software claim | UM §§1.1.4.2, 2.3.4.2 and Table 6-5 (PDF 50–51, 103–104, 272–273) state SP/DP hardware support and DP instruction timing; UM §4.5.7.2 (PDF 188 / 4-30) says some DP FP instructions enter software emulation. This contract uses the explicit opcode/timing tables. | Look for errata or silicon condition before claiming exact DP trap behavior for a particular mask revision. |
| NI status/enables | UM §2.3.4.2 (PDF 103) specifies signed-zero replacement for denormal result; PEM Table 2-4 (PDF 72) defers other NI effects to implementation. | The implemented project policy retains IEEE-derived exception metadata, then flushes a delivered denormal to signed zero. Independent tests check that policy. Exact 603e NI status/enable interactions still need implementation-specific evidence. |
| Estimate bit pattern | PEM `fresx` and `frsqrtex` (PDF 509–513) give error bounds and special values, and permit results to vary between executions. UM Table 6-5 (PDF 272–273) gives timing but no 603e estimate table. | Independent rational checks cover the bounds, required specials, sign, precision and defined metadata. Exact 603e bit reproduction needs an additional implementation source or silicon vectors. |
| Donor metadata | SS supplies five flags only and discards NaN payload, FMA and PPC control semantics. | The isolated donor fails qualification (16,879/47,736 mismatches). The replacement SystemVerilog backend supplies PPC classification, round/discard metadata and nine invalid causes; independent per-op verification is recorded in `sim/fpu/PRODUCTION.md`. |
| Core attachment | The standalone shell owns 32 FPRs and FPSCR; the core retains MSR, final CR, completion and LSU transport. | `FPU_INTERFACE.md` defines tagged issue/result, cancellation, commit-only state, atomic memory preparation and store authorization. The separate integration process must implement those obligations and CPU-level tests. |

## Donor provenance and extraction boundary

The authorized arithmetic candidate is Grabulosaure/ss at commit `70203e26e981069710e934600fd55b9d866a9e5b`: [`fpu_calc.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd), [`fpu_pack.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd), [`fpu_mul.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_mul.vhd), [`fpu_div.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_div.vhd). Preserve original copyright/notices; source headers refer to `lic.txt`, absent in the reviewed checkout, so this document assigns no new license. The user's SS reuse authorization is recorded in the assessment. F1 isolates the arithmetic boundary for qualification: raw operands/opcode/rounding in, raw result and exception/round/class metadata out. SPARC FSR, traps, register file and CPU-facing decode do not own PPC state. [FPU reuse assessment, “SS findings” and F0–F1 gates; linked pinned source]

This contract maps to P23 (FPR/FPSCR shell and memory), P24 (basic/fused arithmetic), and P25 (divide/estimates). Unresolved source conflicts limit silicon-conformance claims; the selected rules remain explicit and independently testable. Core integration and 603e pipeline throughput remain separate acceptance gates. [FPU reuse assessment, F2–F5 gates]


## Review record

Recorded: `git diff --check`; bounded `pdftotext -layout -f/-l` manual review, commit `6d0f2d3` plus uncommitted F0 documentation, 2026-09-27.

Manual review covers all 32 FPSCR bit positions and the supported instruction
classes above. Independent spot checks included UM PDF 103–106, 186–189 and
270–276, and PEM PDF 127–128, 143–144, 492–493 and 509–514. The explicit
source-conflict rows limit acceptance; this is a specification review, with
zero RTL tests or synthesis runs credited to F0.

### Official errata cross-check

The [official MPC603EUMAD/D errata](https://www.nxp.com/docs/en/reference-manual/MPC603EUMAD.pdf)
clarifies precise enabled FP exceptions (§4.1 correction, physical PDF p.8),
but the reviewed corrections do not resolve the vector/update discrepancy.
The [official Rev. 3 manual](https://www.nxp.com/docs/en/reference-manual/MPC603EUM.pdf)
retains both the FE-gated program route (Table 4-1, physical PDF pp.65, 161;
§4.2.2, p.169) and the emulation/no-update/regardless-of-FE paragraph
(§4.5.7.1, p.184). Its NI description still specifies only signed-zero
replacement (§2.3.4.2, p.100). This cross-check does not change the selected
Table 4-1/PEM behavior or establish the unresolved silicon semantics.
