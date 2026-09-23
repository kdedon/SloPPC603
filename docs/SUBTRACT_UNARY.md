# Unary extended subtraction — round 21

SUBFME/SUBFZE implement eight OE/Rc forms, bringing the bounded reviewed and
executable subset to 114 forms. Immediate subtract remains pending.

## Source and execution contract

Primary 603e UM Tables A-1/PDF368 (A1-212/213, raw `subfmex`/`subfzex`),
A-3/PDF377 and A-41/PDF396 establish opcode31, XO9=232/200 and reserved rB=0.
The masks are 0xfc00ffff, with bases0x7c0001d0/0x7c000190 plus OE<<10 and Rc.
All nonzero reserved rB encodings are rejected by the bounded implementation.

Secondary 601UM PDF764/10-210 and PDF765/10-211 specify ~A+ffffffff+CA and
~A+CA. Signed mathematical results are −A+CA−2 and −A+CA−1. CA is read and
replaced on every form. SUBFME clears CA only for A=ffffffff with incoming CA0;
SUBFZE sets CA only for A=0 with incoming CA1. Carry uses the unsigned fixed
operand, while overflow uses the signed mathematical result. OE updates OV and
sticky SO; Rc records the final result with final SO.

The decode-only change reuses ALU_SUBFE and injects B=ffffffff/0 via the immediate
operand path. rA, including r0, remains real; there is no rB dependency. The
existing flag owner and dispatch capture preserve CA across waits and recovery.
No ALU operation, packet field or interface is added.

Primary Table6-4/PDF271 supplies TIM-T64-037/035: raw [o][.] forms, Integer
execution, base one-cycle execution for PID6/PID7v. No full processor timing or
new Quartus fit/resource/timing claim follows from this bounded slice.

## Verification

- `test-core-subunary`: 1,204 symbolic words, 1,152 retirements and 89,010
  complete-state checks. Each instruction retires 113 times. Nine A boundaries
  cross both incoming CA values and all OE/Rc forms; 144 immediate ADDE consumers
  verify carry replacement. A 64-instruction aliasing chain stresses repeated
  reads/writes of one register. SO0/SO1, real r0 and full architectural state are
  covered. The oracle uses signed subtraction and unsigned comparison.
- `test-subunary-execution`: 145 literal checks with pending rA, captured fixed
  B/CA/SO, mutated live controls and held result packets. Includes SUBFME A=max
  overflow at CA0 but not CA1, and SUBFZE A=min overflow at CA1 but not CA0.
- `test-subfme-recovery` / `test-subfze-recovery`: 3,434 checks each. Real
  instructions seed CA0/CA1 respectively; candidates set/clear CA, and redirected
  ADDE consumes the surviving value. RS/IU/CQ kills and kept finish/commit cuts
  also verify exact flag ownership and complete GPR/CR/XER state.
- Two additional Python tests check all nonzero rB values across eight form
  masks, rejected metadata mutation and literal carry/overflow anchors.
- Decoder: 15,808 compiled probes, 732 accepted by both metadata and RTL.

Independent source and RTL review found no actionable findings. Source inventory
now has 56 boundedly reconciled rows and 170 pending. Next: SUBFIC immediate
subtraction with carry, followed by remaining immediate integer forms.

Round21 integration passes all 50 prior RTL targets, strict core/wrapper lint, 116 tool tests and 15 recovery-model tests. No failures remain.

Round22 subsequently accepts [SUBFIC](SUBFIC.md); the current reviewed/executable subset has115 forms. Earlier pending statements describe round21.
