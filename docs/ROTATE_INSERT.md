# Rotate word insert — round 17

RLWIMI implements primary opcode20, Rc0/Rc1. All 90 currently reviewed forms now
execute; this bounded set is not the complete 603e ISA.

The existing two rename read ports capture rS and the previous rA mapping before
allocating the new rA destination. SH is a separate five-bit dispatch/issue field,
held with the mask and producer identity. Thus rS=rA and real r0 retain normal
producer matching and recovery semantics without a third rename read port.

The result combines rotated rS inside the inclusive MSB-first MB/ME mask with
old rA outside it. Masks wrap when MB>ME. Rc records the merged result and
captured SO; both forms preserve all of XER. Existing RLWINM/RLWNM behavior is
unchanged. The source opcode-table discrepancy remains documented in ISA_MATRIX.

## Verification

- `test-core-insert`: independent symbolic interpreter selects each output bit
  from rS or old rA. All 1,024 MB/ME pairs run in both Rc modes; additional cases
  cover every SH, full/single/wrapped masks, rS=rA, real r0, chained destination
  writes, SO0/SO1 and negative/positive/zero merged results. The 2,891-word corpus
  retires 2,839 instructions, including 2,245 RLWIMI operations, with 218,905 checks
  of complete GPR/CR/XER/LR/CTR state, exact retirement path and memory digest.
- `test-insert-execution`: 73 literal checks with pending rS or old rA, mutated
  live SH/mask/flags after dispatch, exact wake identity and stable result packets.
- `test-insert-recovery`: 3,445 checks; an older ADDI has produced rA=1 while architectural rA
  is still zero. RLWIMI must merge that renamed value, preserving its low bit.
  RS/IU/finished-CQ kills and kept finish/commit redirects check the surviving
  GPR/CR/XER state and exact producer ownership.

The old rotate bench now tests opcode22 rejection in both Rc modes; obsolete
RLWIMI rejection expectations are replaced by the accepted execution coverage.
Direct dispatch fixtures tie the new SH input to zero for established operations.
Targeted independent RTL review found no actionable issues.

This adds no full timing-conformance or Quartus fit/timing claim. The next bounded
integer work is source/metadata preparation for SUBF/NEG and their CA/OE/Rc forms.

Round17 integration: all 36 prior RTL targets, strict core/wrapper lint and 120 Python tests pass. The strengthened insert recovery fixture passes 3,445 checks. Compiled decode passes 15,808 probes with 660 accepted.
