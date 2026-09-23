# Low-word multiplication

Round 29 added MULLI and the four MULLW OE/Rc forms. They use the tagged IU result, GPR forwarding and recovery path. The current milestone adds conservative multicycle reservation; [MULTIPLY_TIMING.md](MULTIPLY_TIMING.md) defines its accepted-edge contract and limits.

MULLI multiplies a real rA (including r0) by the sign-extended 16-bit immediate and writes the low 32 product bits, without changing CR or XER. MULLW multiplies two signed 32-bit inputs and writes the low 32 bits. OE sets OV when the full signed product cannot fit in signed 32 bits and accumulates sticky SO. Rc classifies the low-word result and records the final SO. CA and non-CR0 fields remain unchanged. Source/destination register aliases are supported by existing operand capture.

The implementation computes an explicit signed 64-bit product and compares its upper half against the sign extension of the low half to detect overflow. MULLI uses a distinct internal ALU operation so its three-cycle timing family remains known after issue; no external port or packet field changes. Result backpressure, cancellation and retirement permissions use the existing mechanisms.

## Sources and boundaries

Primary 603e UM PDF366 (Table A-1), PDF389 (D-form) and PDF396 (XO-form) anchor the encodings. MULLI uses primary opcode7, mask/value `fc000000/1c000000`. MULLW uses primary31/XO235, with fixed-form mask `fc0007ff`; OE and Rc select the four values from base `7c0001d6`.

Secondary MPC601UM PDF697/698 (printed10-143/10-144) provides semantics. Its MULLI product slices have an off-by-one width inconsistency, and the MULLW pseudocode uses 64-bit register slices despite the 32-bit context. The bounded implementation follows the low-32-bit prose and explicit signed overflow rule; the discrepancies remain in ISA source metadata. 601-specific MQ effects and timing are not imported into the 603e.

The primary timing records TIM-T64-002 and TIM-T64-039 list 2/3-cycle MULLI and 2/3/4/5-cycle MULLW cases. The manual does not map operands to those counts. The bounded IU selects the documented maximum, producing accepted finish at E+3 and E+5 respectively. Lower operand-selected timing, a staged multiplier datapath, dual issue and silicon scheduling equivalence remain open. No new FPGA timing or fit claim is made.

## Validation

The independent symbolic program contains 2,166 words and retires 2,114 instructions under stalls, with 163,078 full-state checks. It includes signed boundaries, 272 MULLW executions across all OE/Rc combinations, 80 MULLI executions, real r0 inputs, destination/source aliases, dependent chains and flag preservation. Literal Python tests check product and encoding anchors independently.

Two recovery variants add 3,809 checks each: minimum-signed times one clears OV with sticky SO retained, and minimum-signed squared overflows with low word zero. Both begin with nonzero CR/XER state, preserve carry through the multiply and check cancellation during the reserved execute interval plus retained finish/commit.

Direct execution now adds 79 checks for delayed operand wake, captured SO/permissions, no early finish and held results. Decoder validation adds 605,185 checks, including every MULLW register/OE/Rc combination and all MULLI immediate values. The timing-specific direct and actual-core gates add 76 and 27 checks. Final integration results are recorded in WORK_QUEUE.md.
