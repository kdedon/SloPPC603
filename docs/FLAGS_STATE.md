# CR/XER state foundation

The CX-I02 implementation adds full-width committed CR and XER registers and a single speculative owner identified by completion slot and generation. It follows [CR_XER_CONTRACT.md](CR_XER_CONTRACT.md). This foundation originally served 15 flag-free forms. [Record-logical execution](RECORD_LOGICAL.md) extends it with ownership acquisition and captured SO for CR0 writers. [ADD/ADDC execution](ADD_FLAGS.md) now exercises CA/OV/SO writes; ADDE now captures committed CA; [ADDME/ADDZE](ADD_UNARY.md) now implement captured-carry decrement/increment.

## Packet and state path

Allocation supplies `needs_flags`, `write_ca`, `write_ov_so`, and `write_cr0`. The completion queue clears these for diagnostics, treats any flag write as requiring ownership, and clears speculative deltas on allocation. Result packets contain candidates `ca`, `ov`, `so`, and `cr0`; the producer cannot grant write permissions. Only an accepted live, unfinished, exact-generation result stores candidates under the allocated enables. The resulting retirement packet includes `cr_delta` and `xer_delta` along with the GPR result.

`ppc_flags` applies the masked delta using the same accepted retirement event as the architectural GPR file. Its masks permit CR0 and XER CA/OV/SO only. Other bits are preserved. A stalled retirement changes no architectural state. An inconsistent owner is an assertion failure, not a separate handshake that could split GPR and flag commitment.

Admission uses pre-edge ownership: an owner retiring this edge does not make the token available to another flag instruction until the next edge. Flag-free allocation does not need the token. Recovery uses the completion queue's post-commit survivor metadata and exact identities. An owner absent from that prefix is released; a surviving owner remains occupied. Reset clears CR, XER and ownership together.

The core now connects record-logical ownership acquisition and CR0 permissions through atomic dispatch, with captured SO held through execution. ADD/ADDC now drive the allocated CA and OV/SO write enables.

## Validation commands

```sh
make -C ppc603e/sim test-flags test-completion-flags
make -C ppc603e/sim lint test
make -C ppc603e/sim check-spec test-recovery
```

The independent `sim/tools/flag_state.py` reference composes reviewed arithmetic-family equations with allocated masks and an atomic architectural-state update. Its owner model consumes flag-owning identities from an already accepted, post-commit recovery snapshot; it does not decide queue age or whether a redirect is admissible. Fourteen focused tests include 500 deterministic mask-preservation cases and deliberate sticky-SO, CR0 relation, split-commit, release-edge and malformed-survivor mutations.

Focused RTL tests and independent Python reference tests provide foundation evidence; they do not establish instruction-level CR/XER execution. Independent review accepted 37 standalone state checks and 168 coupled CQ/flag checks. The coupled bench proves packet removal and flag update share one accepted retirement edge; it does not instantiate the architectural GPR file. Separate [record-logical tests](RECORD_LOGICAL.md) now establish nonzero GPR/CR0 instruction-level commitment and recovery. ADD/ADDC tests now establish nonzero-XER arithmetic commitment and recovery. All existing RTL regressions and 120 Python tests also pass; see WORK_QUEUE and VERIFICATION. The changed RTL has not been remeasured in Quartus.

The [serialized comparison extension](CONTROL_MEMORY.md) adds allocation-controlled BF selection to the existing single-field CR write permission. Original record forms keep field zero; all comparisons preserve XER and the seven nonselected CR fields.

## Round 26 selected CR-field transfer extension

[MFCR/MTCRF](CR_TRANSFERS.md) add full committed-CR reads and eight-bit FXM writes. The allocation-owned `write_cr_fields` permission and `cr_mask` select any combination of CR fields; the result's `value` carries the candidate and completion stores only selected bits in `cr_delta`. The flags unit independently masks retirement. Existing `write_cr0`/`cr_field` stays the one-field path; XER permissions are unchanged. MFCR drains older work before capturing CR and blocks younger dispatch until retirement. MTCRF owns the exact flag token even when FXM is zero. This supersedes the earlier statement that CR transfers remain unsupported, without adding flag forwarding or claiming 603e timing.

## Round 27 single CR-bit extension

[CR logical operations](CR_LOGICAL.md) add allocation-owned `write_cr_bit` and `cr_bit` for one architectural destination bit. Completion consumes only the Boolean candidate in `result.value[0]`, and both completion and retirement mask it independently. Both CR sources come from the pre-operation snapshot, including aliases. Multi-field MTCRF and single-field compare/record paths remain unchanged. No GPR or XER permission is granted, and the same exact-owner recovery contract applies.

## Round 28 CR-state extension

[MCRF/MCRXR](CR_STATE.md) reuse the selected-field `write_cr0` permission. MCRXR also allocates CA and OV/SO clearing; all effects retire atomically from one captured result. XER[28:0] remains preserved, with the reserved-bit source boundary recorded in that contract.
