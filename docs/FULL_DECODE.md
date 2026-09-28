# Complete instruction decode

`ENABLE_FULL_DECODE` makes every 32-bit word either execute or take the
exception the 603e manuals specify; no encoding reaches the decode diagnostic.
It requires `ENABLE_SUPERVISOR_EXCEPTIONS` and `ENABLE_LIVE_CONTEXT`. The
translated MVP profile (`quartus/translated`) enables it. With it clear, the
forms below decode as before (diagnostic).

Target variant: PID7v-603e. There is no FPU, so MSR[FP] never sets; FP
instructions behave as on an FPU-equipped 603e with MSR[FP] = 0.

## Sources

MPC603e UM (see [references/SOURCES.md](references/SOURCES.md)): §2.3.1
(printed 2-16–2-18) instruction classes and boundedly undefined; §2.1.1–2.1.2
and Tables 2-2/2-3 (printed 2-5–2-9) PVR, EAR, HID0, HID1; §1.3.1 PVR values;
§2.3.5.4 external control; §3.1.3 (printed 3-3) ICE/ICFI; §4.5.3 and Table
4-11 DSI (DSISR bit 11); §4.5.7–4.5.8 (printed 4-29–4-31) program and FP
unavailable; Table 7-1 (printed 7-8–7-9) transfer types; §7.2.4.2–7.2.4.3
TSIZ/TBST for external control; Appendix B Table B-1. PEM §6.4.7–6.4.8
(Tables 6-14, 6-15) register settings; §4.2.4.6 trap conditions; Table 8-15
mtspr encodings.

## Decode classes

| Class | Encodings | Result |
|---|---|---|
| Illegal primary | 1, 2, 4, 5, 6, 9, 22, 30, 56, 57, 58, 60, 61, 62 | Program, SRR1 bit 12 |
| Unused extended | every unlisted XO of 17, 19, 31, 59, 63 | Program, SRR1 bit 12 |
| Not implemented | fsqrt, fsqrts, tlbia (Table B-1); all-zero word | Program, SRR1 bit 12 |
| Invalid form | see [Invalid forms](#invalid-forms) | Program, SRR1 bit 12 |
| FP | lfs[u][x], lfd[u][x], stfs[u][x], stfd[u][x], stfiwx, all 59/63 arithmetic, moves and FPSCR forms | FP unavailable 0x800 |
| Trap | tw, twi | Program, SRR1 bit 14, when a TO condition holds |
| SPR | PVR, HID0, HID1, EAR | See [SPRs](#sprs) |
| External control | eciwx, ecowx | Word access; DSI when EAR[E] = 0 |

FP forms are classified by primary and extended opcode alone (UM §2.3.1: the
class follows the opcode); reserved fields and Rc are not checked. An FP load
or store makes no memory access.

## Invalid forms

Reserved-field and form errors are boundedly undefined (UM §2.3.1.1). The PEM
§6.4.7 lets an implementation take the illegal-instruction program exception
for them; this design always does, except for `sync`:

| Form | Choice |
|---|---|
| Any reserved field or reserved Rc nonzero (X/XL/XFX/D forms other than FP) | Illegal |
| Load with update, rA = 0 or rA = rD; store with update, rA = 0 | Illegal (UM §2.3.4.3.2–3) |
| lmw with rA in the loaded range | Illegal (UM §2.3.4.3.6) |
| lswi/lswx with rA or rB in range, zero XER count | Execute (603e accepts, UM §2.3.4.3.7) |
| bc/bclr/bcctr with an undefined BO; bcctr that decrements CTR | Illegal |
| sc other than 0x44000002 | Illegal |
| lwarx with Rc = 1, stwcx. with Rc = 0 | Illegal |
| sync with bits 9–10 (later-architecture L) nonzero | Executes as sync: a full sync satisfies every weaker form |
| Other sync/eieio/isync/rfi/tlbsync reserved bits | Illegal |
| mfspr/mtspr to an undefined SPR, or mtspr to read-only PVR | Privileged when MSR[PR] = 1 and spr[0] = 1 (UM §4.5.7); otherwise illegal |
| XO 371 (mftb form) with any SPR | Reads like mfspr (603e ignores the difference) |

## Exceptions

| Event | Vector | SRR0 | SRR1 |
|---|---|---|---|
| Illegal | 0x700 | instruction | MSR bits 0, 5–9, 16–31; bit 12 set |
| Trap | 0x700 | instruction | same MSR bits; bit 14 set |
| FP unavailable | 0x800 | instruction | same MSR bits; 1–4 and 10–15 clear |
| eciwx/ecowx, EAR[E] = 0 | 0x300 | instruction | 0–15 clear; DSISR bit 11 (bit 6 for ecowx), DAR = EA |

MSR changes follow the common exception entry. A problem-state trap, illegal
word or FP instruction enters supervisor state as usual. In TGPR mode (TLB
miss handlers) every exception still stops at the existing diagnostic; this
is unchanged by this feature.

Trap conditions (PEM §4.2.4.6), TO bits 0–4: signed less, signed greater,
equal, unsigned less, unsigned greater; twi sign-extends SIMM. A trap that does
not fire completes as a no-op. Traps, FP-unavailable and HID0 writes are
fenced like other context operations and refetch the next instruction.

## MSR[FP], FE0, FE1

`mtmsr` and `rfi` accept FP, FE0 and FE1 instead of stopping. FP is not stored
and reads as zero, so every FP instruction keeps taking FP unavailable. FE0
and FE1 are stored and have no effect: no FP-enabled exception can occur.

## SPRs

| SPR | Number | Read | Write |
|---|---|---|---|
| PVR | 287 | `PVR_VALUE`, default 0x00070200 (PID7v, UM §1.3.1.1) | Illegal (privileged in problem state) |
| HID0 | 1008 | Stored bits | Masked by `HID0_WMASK` = 0xbff9fc99 |
| HID1 | 1009 | `PLL_CFG` in bits 0–3, rest zero | Accepted, no effect (read-only) |
| EAR | 282 | E and RID | Masked to E (bit 0) and RID (bits 28–31) |

All four are supervisor-only (spr[0] = 1). Hard reset clears HID0, HID1 and
EAR, except that the translated top resets HID0[ICE] to its
`RESET_CACHE_ENABLE` so ICE matches the cache mode (the manual's reset value
has ICE = 0; the top keeps its existing default of an enabled cache).

HID0 bits with an effect:

| Bit | Name | Effect |
|---|---|---|
| 16 | ICE | A change issues a cache command: disable routes fetches to single-beat bypass, enable returns to line fills |
| 20 | ICFI | A write with ICFI = 1 issues a flash invalidate |

A write that changes ICE or sets ICFI fences fetch, waits for the command to
complete, then refetches the next instruction. The command uses the external
maintenance handshake described in [ICACHE_CONTROL.md](ICACHE_CONTROL.md): the
cache invalidates on every mode change, a superset of the manual (the 603e
keeps tags while disabled). An external command wins a same-cycle tie; the
external port still works, and HID0[ICE] does not track modes it sets.

Stored without effect: EMCP, EBA, EBD, SBCLK, EICE, ECLK, PAR, DOZE, NAP,
SLEEP, DPM, RISEG, NHR, DCE, DLOCK, DCFI (no data cache), ILOCK (cache locking
is not implemented), IFEM, FBIOB, ABE, NOOPTI (dcbt/dcbtst are already
no-ops). Reserved bits read as zero.

## External control

eciwx/ecowx are word accesses with EA = (rA|0) + rB, user level. With EAR[E] =
0 they take a DSI without a bus transfer. Otherwise they translate like loads
and stores (a direct-store segment still gives DSI) and use TT 11100 (read) /
10100 (write) with EAR[28:31] on TBST‖TSIZ[0:2]. A misaligned EA takes the
alignment exception (PID7v, UM §4.5.6). The alignment check wins over the
EAR[E] DSI.

## 60x transfer class

Each data request carries `dmem_attr_t {kind, rid}`. `ppc_core_bat` holds it
with the lane's single outstanding request; `ppc_bus60x_arbiter` and
`ppc_bus60x` carry it to the pins:

| Source | TT |
|---|---|
| lwarx | 11010 read-atomic |
| stwcx. with the reservation | 10010 write-with-flush-atomic |
| eciwx / ecowx | 11100 / 10100, TBST‖TSIZ = RID |
| Other loads / stores | 01010 / 00010 (unchanged) |

A stwcx. without the reservation still issues only its strobeless probe. There
is no data cache, so lwarx never uses RWITM-atomic.

## FPU entry point

Decode marks every FP-class word `SPECIAL_FPU`. Dispatch converts it to
`SPECIAL_FP_UNAVAILABLE`; a future FPU replaces that step with issue when
MSR[FP] = 1, and unmasks MSR[FP] in `ppc_exception_state` and `ppc_special`.

## Verification

[FULL_DECODE_VERIFICATION.md](FULL_DECODE_VERIFICATION.md).
