# Record-logical execution

The CX-I03 RTL extends `and`, `andc`, `or`, `orc`, `xor`, `nand`, `nor` and `eqv` to Rc=1. Their GPR operand and result rules match the accepted nonrecord forms. CR0 compares the final 32-bit result algebraically against zero and copies captured XER.SO into its low bit. XER is unchanged, as are CR1–7. ADD record/overflow forms are implemented by the separate [ADD/ADDC slice](ADD_FLAGS.md).

## Admission, execution and commitment

Decoded flag reads/writes determine ownership demand. A record instruction allocates CQ, GPR rename, reservation station and the single flag token atomically. Pre-edge ownership decides availability: retirement cannot release and reacquire the flag token at the same edge. Flag-free instructions can continue while the token is occupied, subject to ordinary in-order dispatch and resource availability.

Dispatch captures committed SO with the operation, before any subsequent changes to live inputs. The reservation station preserves SO and the record control while GPR operands wait for an exact tagged wake. The IU holds both through backpressure and computes one complete GPR/CR0 result. The completion queue uses its allocated CR0 write permission to select the delta; the producer does not grant permissions. One retirement event commits the GPR and CR0 together.

Record forms retain E≥D+1, accepted finish F=E+1 and C>F. The combined flag owner is a conservative implementation admission rule, not full 603e scheduling fidelity. The original seven-form stage trace remains a separate unchanged probe. Recovery uses the existing exact owner and post-commit survivor rules from [CR_XER_CONTRACT.md](CR_XER_CONTRACT.md).

## Verification scope

`test-record-execution` directly drives RS/IU operation inputs and checks literal LT/GT/EQ/SO nibbles for SO=0 and SO=1. It changes live SO, record and operation inputs while the captured instruction waits, then tests same-edge wake/issue and held IU results. Its seven cases pass 77 checks. This is explicit unit input stimulus, not a claim that a supported instruction can write XER.SO.

The full-core `test-core-record-logical` is the instruction-level acceptance gate. Its programs use reachable reset-zero XER; the original record-only fixture contains no XER writer; the separate ADD/ADDC corpus now checks record-logical consumption of architecturally set SO. Independent review accepted 10,252 checks with 33 retirements, including 14 record commits and three killed record owners. The oracle predicts dispatch PC/word, classifies a surviving list prefix, checks D/E/F/C and retirement identity, and compares every architectural GPR plus full CR/XER after each edge. It covers all eight families, all result relations, r0 RAW/WAW, stalls, owner release/admission, forwarding before owner commitment, RS/IU/CQ kills, diagnostic cleanup and a kept stalled owner.

`test-core-record-edges` adds 43 focused checks for surviving owner finish and commitment on redirect edges, rejected cuts of a finished head with ready low/high, exact target/fallthrough order, and reset while the owner is in IU or finished CQ. All existing RTL regressions pass.

The original nonrecord logical regression retains its 94 result checks. Its eight terminal tests now toggle the high extended-opcode bit of each logical word, verifying full ten-bit opcode matching; they no longer reject the newly supported Rc bit. The baseline core regression now rejects still-unsupported extended ADD Rc/OE forms.

This record-logical slice does not enable rotate, shift, compare, supervisor or floating-point forms; ADD/ADDC carry/overflow execution is documented separately. FPGA fit and timing have not been remeasured.
