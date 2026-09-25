# Explicit XER access

This bounded slice adds explicit SPR 1 access in the existing
`ENABLE_SUPERVISOR_EXCEPTIONS` profile. That profile switch is an implementation
availability gate, not an architectural privilege restriction: XER is readable
and writable with MSR.PR either zero or one. The default profile remains unchanged.
This work adds neither string operations nor a new timing measurement.

## Reviewed architectural contract

The local primary architectural source is
Programming Environments, Rev. 1 (`MPCFPE.pdf`), section 2.1.5,
Figure 2-6 and Table 2-6 (printed 2-11 / PDF 73). Its XER diagram and table
identify SO, OV, CA, and the seven-bit byte count. In normal RTL numbering these
are bits 31, 30, 29 and 6:0. Architectural bits 3–24 are reserved and the diagram
shows zeros. This implementation normalizes explicit writes and reads with
`0xe000007f`, without importing the MPC601's nonarchitectural compare-byte field.

The same table explicitly distinguishes MTSpr from arithmetic overflow:
writing SO=0 and OV=1 clears SO and sets OV. An explicit write replaces all
implemented XER bits; it must not apply the arithmetic sticky-SO operation.
An all-one source therefore reads back `0xe000007f`, and a source of
`0x40000055` reads back unchanged. Nonrecord MTSpr changes no CR field.

PEM MFSPR and MTSPR UISA tables identify XER as SPR 1 (printed 8-155 /
PDF 567 and printed 8-172 / PDF 584). The encoded SPR halves are swapped
relative to the numerical selector. Both accesses are user-level; a privilege
fault for SPR 1 in PR=1 would be incorrect. The fixed Rc bit remains zero.

The processor-specific primary source is the
MPC603e and EC603e User's Manual (`1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`),
section 2.3.5.1 (printed 2-40 / PDF 118). It explicitly ignores architectural
instruction bit 25, the extended-opcode difference between MFSPR and MFTB.
Consequently XO 339 and XO 371 are equivalent reads for enabled SPR 1 access;
MFTB spelling does not turn SPR 1 into an invalid time-base selector. This
processor rule does not make other reserved instruction fields legal.

PEM MCRXR (printed 8-151 / PDF 563) copies old architectural XER bits 0–3
to the selected CR field and clears them. Reserved bit 3 is zero in this
implementation, so the transferred nibble is `{SO, OV, CA, 0}`. Byte count is
unaffected. Arithmetic flag writes also preserve byte count: only an explicit
XER write in this slice can replace it. Preserving byte count does not implement
LSWX or STSWX, the operations that consume it architecturally.

The 603e manual section 6.3.3.2 (printed 6-13 / PDF 259) lists MTSpr(XER)
and MCRXR among dispatch-serialized instructions. The existing conservative
special-operation drain/retirement interlock is retained; this is not a claim
of cycle-accurate 603e scheduling.

## Ownership and recovery review obligations

The committed XER remains owned by `ppc_flags`. Explicit writes must use the
same allocation-owned flag permission and exact-producer commitment as existing
arithmetic and MCRXR. Special execution may produce a candidate value; it must
not independently mutate committed flags. Allocation, accepted finish and
retirement each retain their established roles. A result payload cannot grant
itself byte-count write permission, and an illegal/faulting packet must lose
all flag write permissions.

Reads capture committed XER after older work drains. A held read result must
remain stable, while a younger explicit write cannot pass it. Branch recovery
may preserve an exact-owner survivor but must suppress a killed or stale result.
Same-edge retirement/recovery retains the existing architectural commit rule;
reset still clears committed XER to zero. Existing update-register and ordinary
GPR retirement semantics are outside this change.

## Production review

The production checkpoint implements `write_xer` in decoded and retirement
metadata. Both explicit reads and writes request the existing exact-owner flag
token. Core dispatch still drains the CQ for special operations, and special
execution captures the three flags and byte count together. MFSPR returns that
snapshot with reserved bits zero; MTSpr returns a candidate source value without
writing architectural state in `ppc_special`.

Completion accepts the candidate only for a live, unfinished, generation-matched
producer outside the accepted recovery kill set. Allocation owns `write_xer`;
illegal allocation and fault completion strip it. Completion masks an explicit
write with `0xe000007f`, and `ppc_flags` independently applies the same mask at
retirement. Existing arithmetic/MCRXR masks remain unchanged. Therefore byte
count is preserved by those operations, and result data cannot grant new write
permission. Architectural commitment remains before recovery's owner cleanup;
recovery does not restore or mutate committed XER.

Review found and corrected one profile mismatch: XO 371 had remained dependent
on `ENABLE_TIMERS`. It now also admits SPR 1 in the supervisor-enabled profile,
so explicit XER access does not require enabling timers. Other selectors retain
their existing profile behavior. The independent verifier owns runtime coverage
and test evidence; this document's production review is not a substitute for it.

All pre-existing FPGA archives describe their recorded source snapshots, not
the XER-enabled revision. No fit or constraint change accompanies this slice.
