# Build status

Current cross-system percentages, gaps and validation boundaries are tracked in
[SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md). Historical milestones below retain
their original scope and dates; later feature contracts supersede early limitations.


**Source revision boundary:** the saved fit below predates the P05 tagged execution refactor. Its source hashes describe that earlier bootstrap; current RTL has not been synthesized or timed.

Date: 2026-09-12. Scope: accepted P04 build setup and early synthesis
foundation. This records the current executable integer scaffold only. It does
not certify a complete 603e, a 60x interface, architectural endian behavior,
PID7v clocking, or final FPGA timing closure.

## Host inventory

| Tool | Observed version/status |
|---|---|
| Verilator | 5.020 |
| GNU Make | 4.3 |
| Host GCC | Ubuntu 13.3.0 |
| Host binutils | 2.42 |
| Docker | client 29.8.0, buildx 0.37.0; daemon usable for the bounded builds |
| PowerPC cross tools on host | not installed |
| Quartus on host `PATH` or under `/opt` | not found |

The container paths avoid host package installation. The PowerPC image is built
from Debian `bookworm-20250811-slim` pinned at
`sha256:b1a741487078b369e78119849663d7f1a5341ef2768798f7b7406c4240f86aef`
and snapshot `20250811T000000Z`. It contains GCC 12.2.0,
binutils 2.40, and Python 3.11.2. `toolchain/evidence/container-image.txt` records
the locally resolved image identity after each run.

The existing Quartus container is
`theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70`,
running Quartus Prime Lite 17.0.2 Build 602.

## Checks run

Commands in this section Run from the repository root.

| Command | Result |
|---|---|
| `make -C sim all` | PASS: strict canonical RTL lint and 3 x 256 integer-result regression, including illegal/Rc/OE rejection, queue pressure, and reset recovery |
| wrapper lint with canonical `rtl/files.f` | PASS under Verilator `-Wall` |
| host `ld -T toolchain/link.ld` with a synthetic object | PASS: explicit reset address, four-byte BSS bounds, aligned `tohost`, separate RX/RW segments, and 4 KiB reserved stack |
| `./toolchain/build-container.sh` | PASS: image build, BE/LE compile/disassembly checks, and reproducibility check |
| `./quartus/build.sh --docker` | Flow/fit PASS on `5CSEBA6U23I7`; TimeQuest completed with timing violations described below |
| `./quartus/collect-reports.sh` | PASS: saved reports and enforced 35 virtual/zero physical pin guard |

The cross checker confirmed ELF32 `EM_PPC`, entry `0xfff00100`, `_start`,
`main`, and global `.tohost` symbols. The first instruction word is
`60 00 00 00` in BE and `00 00 00 60` in LE. Two clean builds produced
identical ELF, binary, and disassembly hashes; the hashes are in
`toolchain/evidence/artifacts.sha256`.

Quartus 17 initially rejected derived local parameters in a module parameter
list and named struct assignment patterns. The canonical FIFO, fetch, and core
now express the same logic with older-tool-compatible syntax. The complete
existing regression passed after those syntax-only edits. No shadow synthesis
RTL remains.

## Bootstrap fit evidence

The measurement wrapper supplies an arbitrary runtime 32-bit instruction word,
so register indices, decoder choices, and ALU choices are not fixed during
synthesis. Clock, reset, all stimulus bits, and the folded activity output are
35 virtual pins. Quartus reported zero physical input pins and zero physical
output pins. The collection script rejects evidence that does not retain this
property.

The final fitter report records:

| Resource | Bootstrap result |
|---|---:|
| Logic utilization | 1,390 / 41,910 ALMs (3%) |
| Registers | 1,729 |
| Block memory | 892 / 5,662,720 bits (<1%) |
| RAM blocks | 5 / 553 (<1%) |
| DSP blocks | 0 / 112 |

These counts include the instruction-response and digest harness. They cover
only the current seven-form, single-dispatch scaffold and are not projections
for the final CPU.

TimeQuest found zero unconstrained clocks, inputs, outputs, and I/O paths, but
the zero-delay virtual-I/O constraints did not meet timing:

| Corner | Setup slack | Hold slack |
|---|---:|---:|
| Slow 1100 mV, 100 C | -0.360 ns | -1.826 ns |
| Slow 1100 mV, -40 C | +0.405 ns | -2.235 ns |
| Fast 1100 mV, 100 C | +7.287 ns | -0.508 ns |
| Fast 1100 mV, -40 C | +9.782 ns | -0.805 ns |

Thus the early compile and fit succeeded, while the 50 MHz timing requirement
is unmet. Quartus also warns that a virtual clock pin is treated as a ripple
clock, so these timing values are estimates under placeholder assumptions.
Saved flow, map, fit, STA, tool, image, and extracted-summary evidence is under
`quartus/evidence/`; `source-sha256.txt` identifies the canonical RTL and project inputs for the measured build.

## Remaining acceptance gaps

- The compiled program cannot run on the current core. `crt0.S` needs branches
  and stores, and `tohost` needs a memory path; those arrive with later integer,
  LSU, and program-harness work.
- The LE artifact establishes tool output byte order only. Architectural
  instruction/data endian rules and end-to-end LE execution remain P26.
- P30 must fit the complete processor, replace placeholder virtual-I/O timing
  with reviewed interface constraints, resolve all setup and hold violations,
  and inspect final RAM/DSP inference and critical paths.
- The single-clock FPGA wrapper is a scaffold convenience. Source audit found
  PID7v does not support a 1:1 clock multiplier, so this is not evidence of a
  supported PID7v hardware clocking mode.
- The abstract fetch and retirement interfaces remain internal to the harness;
  no physical 60x pin contract or board integration is implemented or measured.

This bounded P04a foundation is reproducible and usable for continued work.
Parent review accepts P04’s defined build-setup and early-fit gate. The end-to-end execution, hardware fidelity and final timing requirements above belong to the later implementation gates; they are not marked complete.

P06b1 adds canonical CQ/rename recovery and local RS/IU cancellation logic with core redirect requests tied off. This change has not been measured in Quartus. Existing saved fit/timing reports and source hashes still describe their historical build only.

P06b2 enables explicit core recovery control and changes canonical fetch/IQ behavior. The measurement wrapper ties those control inputs inactive, and no new Quartus build was run. A future recovery-area measurement must account for this tie-off to avoid treating optimized-away recovery logic as measured implementation cost.

P07b expands the canonical IU operation enum/datapath and decoder for eight register-logical forms. Strict simulation checks do not establish their FPGA cost or timing; no Quartus remeasurement accompanies this slice.

## CR/XER foundation measurement boundary

Round 8 widens completion/result/retirement packets and adds `ppc_flags` to both canonical simulation and Quartus source lists. The measurement wrapper includes flag metadata/deltas in its retirement digest. These changes have not been remeasured in Quartus; the historical fit and timing reports do not describe this revision. Current decode produces only zero flag effects, so synthesis may remove the inactive flag state until stateful instructions are implemented.

## Record-logical measurement boundary

Round 9 connects owner-gated record-logical decode, captured SO and CR0 computation. Canonical core and measurement-wrapper strict Verilator lint pass; no Quartus resource, fit or timing rerun has been performed. Historical reports still describe their recorded older source hashes. XER writers remain absent, so reachable SO is zero and synthesis may optimize the current SO path even though the direct execution fixture verifies both SO input values.

## ADD/ADDC measurement boundary

Round 10 adds a widened integer sum, overflow/sticky-SO computation and held CA/OV controls. Canonical and measurement-wrapper strict Verilator lint pass. No Quartus resource, fit or timing measurement has been rerun for this revision. XER status can now become nonzero through supported instructions; historical reports still describe older source hashes.

## ADDE measurement boundary

Round 11 adds captured CA input and carry-sensitive overflow computation, shared by the ADD datapath. Canonical core and measurement-wrapper strict lint pass. No Quartus fit/resource/timing rerun has been performed. The simulation source list remains canonical; changed arithmetic and control widths require a fresh measurement before any FPGA resource or timing claim.

## ADDME/ADDZE measurement boundary

Round 12 adds two operation enum values and immediate operand selection for unary ADD forms, reusing the captured-carry arithmetic and flag path. Canonical core and measurement-wrapper strict Verilator lint pass. Simulation and Quartus retain the same canonical module list. No new Quartus fit/resource/timing measurement was run; historical reports do not describe this revision.

## RLWINM/RLWNM measurement boundary

Round 13 adds a rotate/mask datapath and a captured 32-bit mask in decoded, reservation-station and issue state. Canonical core and measurement-wrapper strict Verilator lint pass, with the existing canonical source list. No Quartus fit/resource/timing rerun was performed. Historical resource and timing reports describe older source hashes; these new registers and logic have not been measured on FPGA.

## Serialized control/memory measurement boundary

The temporary milestone adds `ppc_special.sv` to both canonical simulation and Quartus source lists, a third committed GPR read, selected CR-field metadata and explicit CQ empty/finish outputs. The core exposes an abstract uncached data interface. Existing unit callers tie its inputs inactive; the measurement wrapper likewise ties it off and includes the new CR-field selector in its retirement digest. Strict core and wrapper Verilator lint pass. No Quartus fit, resource or timing rerun was performed; inactive memory inputs may optimize away or permanently stall parts of this lane in the wrapper, so no area/timing conclusion follows.

## Logical-shift measurement boundary

Round15 adds ALU_SLW/ALU_SRW and two decode cases without changing ports, packet widths or canonical module lists. Core and measurement-wrapper strict lint pass. No Quartus fit/resource/timing rerun was performed; the new shift logic is not covered by historical FPGA measurements. All sixteen values of the current four-bit ALU enum are now assigned.

## Round 16

SRAW/SRAWI add ALU_SRAW and widen alu_op_t to five bits, increasing internal packet widths. No module ports or canonical source lists change. Strict core/wrapper lint passes; no new Quartus fit, resource or timing measurement is claimed.

## Round 17

RLWIMI adds ALU_RLWIMI within the five-bit enum and a five-bit SH field in uop/issue packets and the reservation station. Dispatch gains shift_i; the core wires it and all direct fixtures tie it appropriately. Canonical source lists and external core ports are unchanged. No new Quartus fit/resource/timing measurement is claimed.

Round17 strict core and measurement-wrapper lint pass with zero warnings.

## Round 18

ALU_SUBF reuses the existing adder for SUBF/NEG; a selected complemented A and fixed carry-in feed both full-width and low-part sums. Enum width, packets, ports and canonical source lists do not change. Strict core/measurement-wrapper lint passes. No Quartus fit/resource/timing rerun was performed.

## Round 19

ALU_SUBFC joins the existing five-bit enum and shared subtract adder; CA uses the widened sum carry. Packets, ports and canonical source lists are unchanged. Strict core/measurement-wrapper lint passes with zero warnings. No new Quartus fit/resource/timing measurement is claimed.

## Round 20

ALU_SUBFE joins the five-bit enum and complemented-A adder selection, with captured CA rather than fixed carry-in. No packets, ports or canonical source lists change. Strict core/measurement-wrapper lint passes. No new Quartus fit/resource/timing measurement is claimed.

## Round 21

SUBFME/SUBFZE change only decode, selecting existing ALU_SUBFE with fixed B and captured CA. No enum, packet, interface or source-list changes. Strict core/measurement-wrapper lint passes. No new Quartus fit/resource/timing measurement is claimed.

## Round 22

SUBFIC changes only decode, reusing ALU_SUBFC with a sign-extended immediate. Packets, enum, ports and canonical sources are unchanged. Strict core/measurement-wrapper lint passes. No new Quartus fit/resource/timing measurement is claimed.

## Round 23

ADDIC/ADDIC. change only decode, reusing ALU_ADDC and the existing flags path. Packets, enum, ports and canonical sources are unchanged. Strict core/measurement-wrapper lint passes. No new Quartus fit/resource/timing measurement is claimed.

## Round 24

ANDI./ANDIS. change only decode, reusing ALU_AND and the record-result path. Packets, enum, ports and canonical sources are unchanged. Strict core/measurement-wrapper lint passes. No new Quartus fit/resource/timing measurement is claimed.

## Round 25: unary integer datapaths

CNTLZW/EXTSB/EXTSH add three values to the existing five-bit ALU enum and extend decode/IU logic. No interface, file-order or Quartus QSF changes are needed. Strict core and measurement-wrapper Verilator lint pass with no warnings. No new Quartus synthesis, fit or static-timing run was performed; the existing FPGA timing limitations remain.

## Round 26: selected CR-field transfers

MFCR/MTCRF extend the existing special lane and add allocation/retirement mask metadata. The measurement wrapper consumes the new packet fields in its digest; no new RTL file or external port is introduced. Strict core and wrapper lint pass with zero warnings. No new Quartus synthesis, fit or static-timing run was performed; earlier timing limitations remain.

## Round 27: CR bit operations

The special lane, allocation/retirement packets and measurement-wrapper digest now include selected-bit CR metadata. No external interface or RTL file-list changes were required. Strict core/wrapper lint passes with no warnings. This round does not include a new Quartus fit or timing result. The independent bus-table/query task changes no hardware.
