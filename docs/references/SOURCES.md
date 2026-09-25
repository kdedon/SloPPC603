# Source audit and architectural decisions

Audit date: 2026-09-12. This is P01's primary-manual audit, not the P02 timing/bus transcription or a claim that RTL implements the findings. PDF page numbers below are **one-based physical pages**. Printed labels are those on the page, so PDF 177 and printed 4-19 identify the same page of the 603e manual. The named PDF manuals are external local references, not files in this repository. See [the reference index](README.md) for the current layout.

## Inventory and completeness

| ID / local file | Observed contents and coverage | Use and limits |
|---|---|---|
| **UM**: `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf` | 455 pages; title PDF 3 identifies MPC603EUM/AD, 11/97, with 603 supplement. Chapters 1-9, appendices A-C, glossary and index have continuous printed numbering; mapping below. | Primary 603e implementation source. The original brief's assertion that this copy is abridged by about 300 pages is **unsupported and rejected**. No missing numbered content was found. This does not establish absence of editorial errors or availability of later errata. |
| **PEM**: `MPCFPE.pdf` | 828-page PowerPC Programming Environments Manual, MPCFPE/AD 1/97 Rev. 1, obtained from the [official NXP archive](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf) for round 37. SHA-256 `0600de0a3cb81636b9d511aa6b185e2fccc02f895ce4630411725634ef8e7eee`. | Primary architectural details explicitly delegated by the 603e UM: 32-bit BAT formats/protection and exception/return behavior. Read the 32-bit sections; 603e-specific UM behavior takes precedence. This addition does not certify every page or close the ISA inventory. |
| **601UM**: `MPC601UM.pdf` | 777 pages. PDF 1 cover, PDF 2 blank, PDF 3-10 About This Book (printed xli-xlviii; OCR truncates some labels), PDF 11-776 continuous chapters 1-10, PDF 777 closing notices. No contents pages or appendices A-I are present, although the text refers to them. | Secondary per-instruction descriptions in chapter 10. The original brief's local appendix A/C/H references are unavailable in this copy. Never import 601-specific timing, exception, cache, bus or POWER behavior as 603e requirements. |
| **602HW**: `MPC602EC.PDF` | 26 pages; cover PDF 1 identifies MPC602EC/D, 5/96, preliminary hardware specifications. PDF/printed pages 2-25 run through §1.8 ordering information; PDF 26 closing notices. | Hardware-specification document, **not the 602 user manual**. §1.1.1 supports basic resources, but does not provide a full 602 ISA/exception contract. No internal numerical gap found in numbered body. |
| **601TS**: `MPC601.pdf` | 32 pages; cover PDF 1 identifies MPC601/D, 11/93; technical summary body PDF/printed 2-31, PDF 32 closing notices. | Historical overview only. No internal numerical gap found in numbered body; not a 603e specification. |
| **MCM**: `G5220297-00_Odyssey_MCM_Feb97.pdf` | 247 pages. IBM preliminary 603e + 660 bridge module/reference-system document. PDF 1-20 front matter; sections 1-13 start at PDF 21, 29, 55, 69, 103, 119, 135, 141, 163, 167, 185, 203, 220 respectively. Section 13 says schematics are separately numbered (PDF 220, printed 13-1); final PDF pages contain image-only material that text extraction cannot inventory as numbered text. | System context and bridge examples, particularly endian §11. Do not promote bridge policy into a CPU requirement. Full schematic-sheet completeness is **not certified** by this bounded CPU audit. |
| **MIT**: `416591138-MIT.pdf` | 52 pages; title PDF 1, abstract/title PDF 3, references PDF/printed 52. Thesis: *An FPGA Implementation of Multicore, Multithreaded PowerPC Processors with Memory Subsystem Using Bluespec*, Alessandro Yamhure. | Non-normative implementation ideas. No claim of 603e fidelity; exhaustive thesis page/schematic audit is not required for CPU requirements. |

The separate *PowerPC Microprocessor Family: The Programming Environments* is **not local**. UM explicitly calls itself its companion (PDF 29-32, printed xxvii-xxx); UM §2.3.2 refers detailed byte-order conventions to it (PDF 96-97, printed 2-18-2-19). Its absence explains why this complete implementation manual lacks a full per-instruction architecture book. Also absent: a 602 user manual, exact chosen-mask 603e errata, and the PID-specific 603e hardware specifications named in UM PDF 33-34 (printed xxxi-xxxii).

### UM page map

Within each range, `PDF page = first PDF page + printed page number - 1`. Every page in the following numbered ranges was checked for the expected footer, including blank numbered ending pages.

| Part | Printed pages | PDF pages |
|---|---|---|
| Contents / illustrations / tables / About This Book | iii-xxxviii | 5-40 |
| 1 Overview | 1-1 through 1-38 | 41-78 |
| 2 Programming Model | 2-1 through 2-48 | 79-126 |
| 3 Instruction and Data Cache Operation | 3-1 through 3-32 | 127-158 |
| 4 Exceptions | 4-1 through 4-38 | 159-196 |
| 5 Memory Management | 5-1 through 5-50 | 197-246 |
| **6 Instruction Timing** | **6-1 through 6-30** | **247-276** |
| **7 Signal Descriptions** | **7-1 through 7-32** | **277-308** |
| **8 System Interface Operation** | **8-1 through 8-46** | **309-354** |
| 9 Power Management | 9-1 through 9-6 | 355-360 |
| A PowerPC Instruction Set Listings | A-1 through A-46 | 361-406 |
| B Instructions Not Implemented | B-1 through B-6 | 407-412 |
| C PowerPC 603 Processor System Design and Programming Considerations | C-1 through C-22 | 413-434 |
| Glossary | Glossary-1 through Glossary-8 | 435-442 |
| Index | Index-1 through Index-10 | 443-452 |

PDF 1-4 contain divider/title/notices; PDF 453-455 contain dividers and companion-book notice. Thus all 455 pages are accounted for. P02 has the full local chapter 6/7/8 material: worked figures 6-3/6-4 at PDF 256-257 (6-10-6-11) and figure 6-5 at PDF 263 (6-17), resource rules at PDF 267-268 (6-21-6-22), and tables 6-1 to 6-6 at PDF 269-276 (6-23-6-30).

### Secondary lookup maps

601UM chapter starts and final labels: 1 PDF 11-46 (1-1-1-36); 2 PDF 47-122 (2-1-2-76); 3 PDF 123-218 (3-1-3-96); 4 PDF 219-248 (4-1-4-30); 5 PDF 249-298 (5-1-5-50); 6 PDF 299-364 (6-1-6-66); 7 PDF 365-456 (7-1-7-92); 8 PDF 457-492 (8-1-8-36); 9 PDF 493-554 (9-1-9-62); 10 PDF 555-776 (10-1-10-222). Each numbered chapter body is continuous. In particular **601UM printed 10-n = PDF 554+n**.

For MCM §11, **printed 11-n = PDF 184+n**, n=1-18. For its CPU-bus section 3, printed 3-n = PDF 54+n, n=1-14. The original source brief's MCM chapter identification was correct; its role remains system evidence.

## Reference precedence

1. Chosen-model/revision primary statements and applicable errata govern implementation-specific requirements. Within this UM, explicitly PID-specific statements take precedence over generic text when they directly describe the difference. Conflicts remain logged, not silently rewritten.
2. Architecture semantics must agree with a PowerPC architecture source and the UM's supported/unsupported instruction lists. Until the missing Programming Environments Manual is obtained, annotate any fallback 601UM semantics with exact section/page and check for a 601 distinction. A 601 pseudocode implementation is evidence to review, not automatic authority.
3. MCM supports explicit 660-backed system scenarios. Its bridge behavior and older-model limitations do not override PID7v statements.
4. Software references and FPGA/thesis examples are secondary checks. Their license/model coverage audit belongs to P01/P13; they cannot establish cycle timing or repair conflicting primary evidence by themselves.
5. `IMPLEMENTATION_PLAN.md` is the project brief, not technical evidence. The decisions below correct its assumptions without claiming the target's fidelity requirements have been met.

## Verified architectural anchors

| Topic | Evidence and conclusion |
|---|---|
| IQ and dispatch | UM §1.1.3.1, PDF 49 / 1-9, and §6.3.1, PDF 252-253 / 6-6-6-7: six IQ entries, up to two fetched and two dispatched each cycle, reservation station at IU/FPU/LSU/SRU. The third instruction mentioned by the overview is the BPU path; §6.3 PDF 251 / 6-5 explicitly distinguishes one branch plus two dispatch-queue instructions. It is not a three-slot general dispatcher. |
| Completion | UM §6.3.3, PDF 258 / 6-12: five completion buffers, allocated at dispatch; at most two completion-unit retirements per cycle. §6.6.1.3 PDF 268 / 6-22 restricts CQ[1] to integer or load, requires CQ[0] completion, and limits the pair to one CR, two GPR and one FPR updates. The P00 practice of inserting only finished results is scaffold behavior, not this allocation contract. |
| Renames | UM §6.3.3.1, PDF 258 / 6-12: five GPR and four FPR renames and one each CR/LR/CTR. **Qualification:** §6.3 PDF 252 / 6-6 separately describes LR rename storage for `mtspr(LR)` and branches that update LR; §6.6.1.1 PDF 267 / 6-21 requires shadow LR availability for branch-and-link. A single undifferentiated LR resource is not yet justified. Load-update can consume two GPR destinations (§6.6 PDF 267 / 6-21). |
| Reservation/store capacity | UM §1.1.3.1 gives one reservation station per nonbranch unit; §6.3 PDF 252 / 6-6 identifies a branch station for CR-dependent conditional branches. These passages do not fully fix storage depth or all admission timing. §1.1.4.3 PDF 51 / 1-11 describes stores held until completion authorization but does not establish a numerical store-queue capacity. Depth choices require a labeled implementation decision plus P02 scheduling checks. |
| Hard reset address/state | UM §4.5.1-4.5.1.1, PDF 176-177 / 4-18-4-19: HRESET handler is `0xFFF00100`; MSR=`0x00000040`, DEC=`0xFFFFFFFF`. Table 4-8 marks GPRs, FPRs, segment registers, TLBs and BATs unknown; caches invalid, tag directory zero with initialized distinct LRU values. FPSCR/CR/XER/TB/LR/CTR/SDR1/SRR0/SRR1/SPRGs/HID0/HID1/miss and compare registers/RPA/IABR/DSISR/DAR/HASH1/HASH2 are zero, subject to EC603e omissions. Unknown is not an architectural guarantee of zero. PVR conflict is logged below. |
| Hard versus soft reset | UM §4.5.1.2, PDF 178 / 4-20: soft reset attempts recoverable state, drains completed stores, does not initialize all latches, disables I-cache, uses IP-selected vector and saves SRR state. §7.2.9.6 PDF 301-302 / 7-25-7-26 specifies external reset timing, including HRESET minimum 255 clocks after PLL lock and SRESET minimum two bus cycles. Internal synchronous scaffold reset does not certify either pin protocol. |
| Endian architectural control | UM Table 4-5 PDF 170-171 / 4-12-4-13 defines MSR[ILE] and MSR[LE]; Table 4-9 PDF 178 / 4-20 and Table 4-7 PDF 175-176 / 4-17-4-18 give exception LE/ILE behavior. UM §2.1.2.2 PDF 87 / 2-9 says miss registers contain big-endian addresses even with LE set. Multiple/string instructions in LE cause alignment exceptions (§2.3.4.3.6-7 PDF 110-111 / 2-32-2-33). |
| Endian data transport | MCM §11.1.1 Table 11-2, PDF 186 / 11-2: aligned sizes 1/2/4/8 use low-address XOR `111`/`110`/`100`/none on CPU bus addressing; §11.1.2 describes CPU lane shifting without reversing bytes. §11.2 PDF 186-187 / 11-2-11-3 describes **bridge** unmunging and byte swapping. This is explicit secondary system evidence, not a formula transcribed from UM §2.3. An abstract byte-addressed RAM and a raw 60x-lane RAM need different contracts. |
| Endian instruction fetch | MCM §11.10 PDF 199-200 / 11-15-11-16 shows cached eight-byte instruction alignment and states uncached four-byte instruction fetch does not munge its address. Figure 11-7 illustrates the wrong result if the unmunger is used. Thus “instruction fetch unaffected” is too broad: fetch-address handling, instruction-word selection, cache representation and external byte steering must be separately specified and tested. This audit does not establish a complete PID7v/32-bit-bus fetch transformation from those figures. |
| Baseline FPU and EC603e | UM PDF 29 / xxvii and §1.1.4.2 PDF 50-51 / 1-10-1-11 support SP/DP and IEEE special values. EC603e has no FPU/FPR file; FP instructions use FP-unavailable exceptions (§6.3 PDF 251 / 6-5; Appendix B PDF 409-410 / B-3-B-4). `fsqrt`, `fsqrts`, and `tlbia` are not implemented (Table B-1 PDF 407 / B-1). `frsqrte` is implemented and is listed `1-1-1`, not an unspecified iterative operation (Table 6-5 PDF 273 / 6-27). |
| 603 differences | UM Appendix C PDF 413-434 / C-1-C-22 is present. §C.1.5 PDF 425-427 / C-13-C-15 gives 8 KiB, two-way caches; appendix also covers direct-store behavior, clock settings and instruction timing differences. 603 is more than a cache-size parameter. |
| 602 evidence | 602HW §1.1.1 PDF/printed 3 explicitly gives 32 **32-bit** FPRs, SP IEEE operation with DP emulation support, four-entry IQ, 4 KiB two-way caches, 32-entry two-way I/D TLBs and protection-only mode. PDF/printed 4 describes a multiplexed external address/data bus. This refutes treating the 602 as merely a cache/TLB/SP flag change in a dual-dispatch 603e. Exact DP instruction traps and `lfd/stfd` legality still need the 602 UM. |

## Decision and conflict log

These are source dispositions and implementation boundaries. They do not silently relax the requested final fidelity.

| ID | Decision / evidence | Owner and boundary |
|---|---|---|
| D01 | Reject the alleged 603e abridgement; all numbered sections are local. Treat absent architecture companion and 601 appendices as distinct gaps. | P01 closed inventory finding; P03 owns missing semantic evidence. P02 is unblocked by PDF availability. |
| D02 | Retain PID7v as the selected reference family. Model version is `0x0007` in upper PVR half; PID6 is `0x0006` (UM §2.1.1 PDF 84 / 2-6). Table 4-8 visibly prints `0003000n` (PDF 177 / 4-19), inconsistent with that explicit model statement. Prefer the model-specific statement; no exact mask revision has been established. | P14/P27 choose and document lower-half PVR value. Do not advertise compatibility with an unverified physical mask revision. |
| D03 | Prefer explicit PID7v divide latency 20, PID6 37 (§1.1 PDF 45 / 1-5; §6.3 PDF 251 / 6-5) over the unqualified 37 in Table 6-4 PDF 272 / 6-26. | P02/P08 must store variant-conditioned timing with both citations; no flat 37-cycle baseline. |
| D04 | IQ=6, CQ=5, GPR renames=5 and FPR renames=4 are anchored. Preserve the additional branch shadow-LR distinction pending a precise allocation model. | P02/P05/P09: do not freeze all LR operations onto a single pool merely from the summary table. |
| D05 | PID7v supports misaligned LE accesses under BE-like exceptions excluding strings/multiples, and rejects misaligned `eciwx/ecowx` (§1.1 PDF 44 / 1-4). This overrides generic older descriptions such as §8.3.2.5.1 PDF 327 / 8-19 splitting misaligned external-control accesses. | P03/P10/P26/P27 use revision-specific alignment tables; MCM older LE restrictions are not PID7v authority. |
| D06 | PID7v IFEM/ABE and cache-fill changes are explicit (§1.1 PDF 44-45 / 1-4-1-5). Generic §6.3.2 PDF 255 / 6-9 and §8.1.1 PDF 310 / 8-2 describe reload blocking; explicit PID7v text instead allows I-cache hits under reload after critical load. | P02/P20/P21/P27 reconcile variant rows before timing/cache acceptance. Inspect detailed §3.1-3.2 and §3.7-3.8 before deciding ABE legality/broadcast behavior. |
| D07 | Hardware ratios are PID6 1/1 through 4/1 (including half steps), PID7v 2/1 through 6/1 (including half steps); PID7v expressly lacks 1/1 and 1.5/1 (UM PDF 44-45 / 1-4-1-5). | P02/P18/P19/P28: original single-clock 1:1 bring-up is a project simplification, not a faithful PID7v clock mode. Final clock-contract disposition remains open; do not silently change the target. |
| D08 | Reject the blanket “fetch unaffected” wording and the attribution of the XOR transport rule to UM §2.3. Keep CPU pin representation and 660 memory representation explicit. | P02/P18/P26 own complete endian contracts, including cache on/off and 32/64-bit bus mode. Until then, no LE conformance claim. |
| D09 | Full IEEE capability does not mean every optional FP instruction is present. Preserve `fsqrt/fsqrts` illegal and EC603e FP-unavailable behavior. `frsqrte` timing must follow its actual row. | P03/P23-P25/P27; 602 remains unsupported as a faithful variant until evidence is obtained. |
| D10 | Resource estimates in the original brief (25-35 K ALMs, about 40 M10K, about 14 DSP; 50 MHz) are **unmeasured estimates/targets**, not evidence of fit or margin. | P04 early synthesis and P30 final fit/timing reports; do not label fit/timing as passed. |

## Remaining evidence and assigned acceptance work

| Item | Owner/task | Conservative boundary / closure evidence |
|---|---|---|
| Exact LR shadow allocation, reservation-station capacities, store-queue capacity, finish/completion/writeback observation points | P02, P05, P09, P10 | Extract all applicable chapter 6 rules and schedules. Where manual remains silent, document a project choice and test its timing implications; do not claim a measured silicon structure. |
| Timing text/table conflicts and missing operand conditions for variable multiply cycles | P02, P08, P12 | P02 must preserve both citations, model conditions, and unresolved operand cases; tests cannot use RTL-derived expectations to resolve ambiguity. |
| 60x signal polarity and precise qualified-grant/ARTRY/DRTRY/TEA sampling windows | P02, P18, P19 | Available anchors: §8.3.1 PDF 317 / 8-9; §8.3.3 PDF 328-330 / 8-20-8-22; §8.4.1-8.4.4 PDF 331-337 / 8-23-8-29. Convert prose and diagrams to explicit cycle scenarios before pin-accuracy claims. Avoid bare Boolean equations that omit active-low conventions or sampling cycles. |
| Pipeline depth, DBWO and bus-mode boundary cases | P02, P18, P19 | §8.2 PDF 316-317 / 8-8-8-9 describes **one additional level**, not two extra levels; §8.4.2 PDF 332 / 8-24 confirms up to two queued data tenures and DBWO fallbacks; §8.10 PDF 351-354 / 8-43-8-46 provides DBWO examples. P02 must transcribe constraints including 32-bit mode and ordering. |
| Revision-specific cache broadcast, critical-word and LE alignment rules | P02, P20, P21, P26, P27 | Reconcile generic sections against explicit PID7v descriptions; do not inherit MCM/PID6 limitations wholesale. |
| Full instruction semantics and optional/reserved-form legality | P03, P07, P13, P23-P25 | Obtain architecture companion or explicitly tag fallback 601UM semantics and resolve implementation-specific differences; absent 601 appendices cannot be cited. |
| Exact PVR revision and silicon errata | P14, P27 | Parameterize/document chosen revision without asserting verified silicon-mask equivalence; acquire matching primary revision/errata evidence before that claim. |
| Complete endian fetch/data/cache/bus mapping, especially PID7v misalignment and 32-bit mode | P02, P18, P26 | Separate raw CPU-lane model from external bridge model; byte-level directed tests must cover instruction order as well as scalar data values. |
| Full 602 exception/ISA/system/bus contract | P03, P27 | Basic 602HW parameters are verified, but a stub cannot count as a 602 implementation. Obtain 602 UM and explicit variant tests. |
| PID7v clock mode versus 1:1 implementation choice; physical AC timings | P02, P28, P30 | Record explicit fidelity disposition. Device setup/hold/PLL electrical fidelity needs missing PID-specific hardware specifications and is outside current logical-cycle evidence. |
| MCM schematic-sheet completeness | P18 only if later using those sheets | Not needed for core contract; inspect separately numbered rendered schematics before relying on a particular board circuit. |

## Audit acceptance record

**Primary-source audit complete:** actual PDF lengths and the entire primary manual's printed-page continuity were checked, key architectural anchors were inspected, original source assumptions were corrected, and unresolved feature evidence has owners and conservative boundaries. This does **not** mark P02 or architectural implementation complete. P01's guideline and software-reference/license portions are separate companion work; see [`CODING_CONVENTIONS.md`](../CODING_CONVENTIONS.md) and the reference audit when integrated.

Method: local `pdfinfo`; `pdftotext -layout`; per-page footer verification of every UM numbered page and every 601UM chapter page; targeted full-page reading. Rendered visual checks confirmed UM Table 4-8 (PDF 177), the branch-resource wording (PDF 252), and MCM Figure 11-7 with its warning caption (PDF 200). PDF text extraction can lose signal overbars, table footnotes and diagram timing edges, so this audit is not permission to use plain extracted text alone for P02 waveforms. Downloaded PDFs were not modified.
