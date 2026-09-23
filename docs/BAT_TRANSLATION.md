# Standalone selected-bank BAT translation foundation

`rtl/ppc_bat_translate.sv` implements combinational translation for one supplied
four-entry instruction or data BAT bank. This is a P17 foundation, not an MMU
or a connection to the current CPU. The caller owns the BAT registers, chooses
the correct bank, and provides a coherent snapshot of registers and MSR inputs.
There is no BAT write/reset mechanism, TLB, segment lookup, page-table search,
architectural exception delivery, or memory transaction in this module.

## Reviewed sources

The primary implementation source is local
`/home/kevin/git/ppc/1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`
(MPC603EUM/AD, 11/97):

| Locator (one-based PDF / printed) | Evidence used |
|---|---|
| PDF 198 / 5-2, Table 5-1 | Separate instruction/data BAT banks and 128 KiB–256 MiB blocks |
| PDF 207–208 / 5-11–5-12, §5.1.6.1 / Figure 5-5 | IR/DR select real addressing; a BAT hit checks protection; a miss proceeds to segment translation |
| PDF 211 / 5-15, Table 5-3 | Block protection faults and translated instruction fetch from guarded BAT memory |
| PDF 216 / 5-20, §§5.2–5.3 | Real-mode PA=EA, instruction WIMG=0001, data WIMG=0011; BATs are not initialized on reset; overlapping mappings are programming errors even with translation disabled |

Detailed architecture fields were obtained from the official NXP-hosted
[PowerPC Programming Environments, MPCFPE/AD, 1/97 Rev.1](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf).
It has 828 pages; downloaded unchanged on 2026-09-14 to `/tmp/MPCFPE.pdf`,
SHA-256 `0600de0a3cb81636b9d511aa6b185e2fccc02f895ce4630411725634ef8e7eee`.
The explicit 32-bit cases were used, not the 601-specific BAT format.

| PEM locator (PDF / printed) | Transcribed rule |
|---|---|
| 321 / 7-33, §7.4.2 | PR selects Vs or Vp for matching; an inapplicable valid bit causes a miss |
| 322–323 / 7-34–7-35, Figures 7-11/12, Table 7-9 | HDL BATU: BEPI[31:17], reserved[16:13], BL[12:2], Vs[1], Vp[0]. BATL: BRPN[31:17], reserved[16:7], WIMG[6:3], reserved[2], PP[1:0] |
| 324 / 7-36, Table 7-10 | BL is 0,1,3,…,0x7ff: twelve sizes from 128 KiB to 256 MiB. BEPI/BRPN must align to block size; otherwise undefined |
| 325–326 / 7-37–7-38, Tables 7-11/12 | PP00 denies; PP01/11 read-only; PP10 read/write; validity selects matching rather than changing this protection table |
| 329 / 7-41, Figure 7-15 | Physical block base combined with unchanged effective block offset |

Relevant register-format, block-size and protection diagrams were visually
checked, along with the local 603e real-mode and translation-exception pages.

## Interface and decisions

Inputs are `valid_i`, `instruction_i`, `write_i`, `ea_i`, `msr_ir_i`, `msr_dr_i`,
`msr_pr_i`, and packed arrays `batu_i[3:0][31:0]` / `batl_i[3:0][31:0]`.
`instruction_i=1` requires the caller to supply IBATs and selects IR; data
accesses require DBATs and select DR. The hardware cannot detect a wrong-bank
snapshot. Instruction+write is an invalid input combination. This module takes
byte addresses and does not check instruction/data alignment or access width.

There is no clock, ready, response queue, cancellation or sampled state. Inputs
must settle before the caller samples outputs. With `valid_i=0`, every output
is zero, including diagnostics. A downstream transaction is authorized only
when `allow_o=1`; PA is zero otherwise. This zero value is not a fallback
translation. `bypass_o` identifies successful real-mode bypass.

For translated accesses, `bat_hit_o` and `bat_miss_o` are exclusive unless a
local configuration error suppresses both. `match_o` identifies the matching
entry and `hit_index_o` its index. A hit can coexist with `protection_fault_o`
or `guarded_fault_o`. `pp_o` and `wimg_o` then retain that entry's attributes,
but `allow_o=0` and `pa_o=0`. If both fault conditions apply, both flags are
reported; architectural exception cause priority is a later integration task.
On a clean miss, neither fault flag is set and no PA is provided. A future
segment/TLB path must handle that miss explicitly.

The following are deliberate bounded-input policies, not claimed silicon
responses to undefined programming:

- Entries with Vs=Vp=0 are ignored, including garbage reserved/length/base bits.
- Any otherwise active entry with reserved bits, invalid BL, or misaligned
  effective/physical base sets its `invalid_entry_o` bit and blocks the bank.
  This applies even when that entry would not match the current PR or EA.
- Effective ranges that overlap and share either validity bit set `overlap_o`.
  The check is independent of current PR, EA, and IR/DR. Opposite, disjoint
  privilege-only mappings are accepted because no access can match both.
  Identical physical ranges at distinct effective addresses are allowed.
- These conditions, and instruction+write, set `config_error_o`. They suppress
  translation and real-mode bypass. `invalid_input_o` specifically identifies
  instruction+write. The result does not emulate register corruption, a machine
  check or an architectural exception for malformed BAT programming.
- No software-write transaction is modeled. Inactive garbage is ignored rather
  than asserting that a preceding reserved-bit register write was legal.

The generic PEM describes IBAT W/G writes as boundedly undefined, while the
603e-specific Table 5-3 explicitly defines guarded BAT instruction-fetch faults.
This implementation follows that specific G behavior on translated instruction
hits. Active IBAT W=1 is rejected as an unsupported input profile; a later
source decision may broaden it. M/I are passed as metadata. There is no claim
that the current instruction cache consumes those attributes. All 16 DBAT WIMG
bit patterns are transported as attributes; this module does not implement or
certify their downstream cache/bus ordering behavior. Real-mode instruction G=1
does not cause a guarded fault because that check applies only with IR enabled.

The translation math uses a masked effective-address comparison and a masked
offset combined with BRPN. The overlap check compares common significant bits
of two aligned effective ranges. No first-hit priority is exposed for overlapping
applicable mappings. No code was copied from DingusPPC or Linux: they were
consulted initially but the official manuals determine this implementation.
In particular, the input validator rejects unaligned BAT bases instead of the
reference emulator's silent masking of those bits.

## Build and checks

From `ppc603e`:

```sh
verilator --binary --timing --assert -Wall --top-module tb_bat_translate \
  rtl/ppc_bat_translate.sv tb/tb_bat_translate.sv --Mdir /tmp/ppc-bat-build
/tmp/ppc-bat-build/Vtb_bat_translate
```

`rtl/bat_files.f` is separate from canonical CPU lists. The bench uses independent
integer interval, division, modulo, and base-plus-offset calculations, together
with hand-calculated anchors. Coverage includes all 12 lengths, four entries,
all Vs/Vp–PR–PP combinations for read/write/fetch, boundaries including the
4 GiB wrap boundary, all 2,048 BL encodings, reserved/base mutations, invalid
entries, overlap/adjacency and disjoint-privilege ranges, every WIMG pattern,
instruction-write rejection, idle gating, and 2,000 deterministic configurations.
RTL results and any independent external vector evidence are recorded below.

An optional `+VECTORS=file` accepts eleven whitespace-separated hexadecimal
fields per line:

```text
controls EA U0 L0 U1 L1 U2 L2 U3 L3 expected57
```

`controls[5:0]={valid,I,write,IR,DR,PR}`. The expected observation packs:

| Bits | Output |
|---|---|
| 56:48 | allow,bypass,hit,miss,PPfault,Gfault,config_error,invalid_input,overlap |
| 47:44 / 43:40 / 39:38 | invalid_entry / match / hit_index |
| 37:6 / 5:2 / 1:0 | PA / WIMG / PP |

The external corpus uses the actual module outputs, not the bench's internal
oracle. Empty or malformed external files fail. No synthesis, FPGA timing,
core integration or full-MMU conformance is claimed.

Final strict Verilator build and direct simulation passed **16,824 checks** on
2026-09-14. The external-vector input path accepted a valid literal observation
and rejected an injected expected-PP mismatch, an empty file, and a malformed
row. `/tmp/ppc-bat-build/direct-run.log` and `negative-results.json` preserve those
results. Regenerable `*.gch` files were removed only from `/tmp/ppc-bat-build`;
the executable, generated sources, logs and test vectors remain.

The parent-owned independent Python interval/addition oracle subsequently passed
**45,312 external vectors** against that frozen executable. Its generator is
`sim/tools/bat_vectors.py`, corpus is
`sim/build/bat/vectors.txt`, and acceptance log is
`/tmp/ppc-round37-bat-independent.log`. This second implementation covers all
sizes/ways, privilege/PP/validity combinations, read/write boundaries, inactive
dirty registers, real-mode controls and attributes, malformed fields/bases,
overlap and disjoint-privilege aliases. Its results complement the direct
instruction-fetch/G-bit and invalid-input anchors; neither lane claims the
missing segment/TLB, core integration, or downstream memory-attribute behavior.
