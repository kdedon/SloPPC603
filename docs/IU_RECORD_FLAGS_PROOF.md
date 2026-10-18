# Standalone IU record-predicate projection

Recorded: `make -C sim test-iu-record-flags-proof` — pending fresh installed execution; baseline commit 75941314a9b5b39b5dfda294fc1e7238def9bdde; date 2026-10-17. The retained physical source has core c6e1730703054c274fe4f08e79350e1457608d1adeebe2d0c9559444e48bd6a6 and IU aa233e4410492acc75d4bc011fcccf0f49dbdd21ec0adc82d0140cf6bc32188e; this standalone draft changes only the IU to 4ceaa6bcb6be6b5e8dbcf60887e92db4b2c929cac0ef9232c0c7ade277e4ab3c. Broader CI remains pending.

The change computes three record predicates before opcode selection instead of selecting a 32-bit record temporary and then reducing it. The actual numerical ALU result, operand/arithmetic state, request/response handshake, CA/OV/SO equations, outer held-compare selection and CR write ternary remain unchanged. The full-profile dead temporary is removed; ADD_COMPARE_ONLY keeps its original local temporary. No pipeline stage, latency, model branch or new port is introduced.

This is the standalone five-fragment change. The historical commit `6f9ab47364f397ace3a267a5f4f3a54589662920` has IU hash 262537f9 with additional NoRec prediction ports; it is not the source installed here. No held-fold, I-page or other former four-cut changes are included.

The optional installed proof reads the actual IU and package, validates complete source/type identities and actual helper/case/output/state authorities, and inverts exactly five frozen fragments to the complete aa233e original. The old reference is reconstructed from fixed literal original fragments, independently of the new helper. Six negative guards reject CR ordering, numerical output, issue acceptance, helper sign, default-op behavior or package changes. Frozen edits and the unchanged stimulus live in readable adjacent JSON with a tool-checked complete identity; no Git history, ignored source copy or former four-cut view loader is required.

```sh
make -C sim test-iu-record-flags-proof
```

For source-only preparation:

```sh
python3 sim/tools/check_iu_record_flags.py --prepare-only --output sim/build/iu-record-flags-proof
```

The generated fixture is byte-identical to the retained standalone actual-source fixture: a6dc2dd8fabff173f5e14c4b5031d6148a6c516f23ae361030888c8f17cf8ba3. Acceptance requires 524,288 complete CR comparisons and 262,144 ADD_COMPARE_ONLY temporary comparisons: 1,024 four-state five-bit opcode forms, 256 control/data patterns and both profiles. Every known opcode, including unsupported encodings, has 256 observations; expected diagnostic counts are 253,952 unknown-op, 1,792 invalid-op and 131,072 unknown-write observations. The removed full-profile temporary is not compared or claimed as an architectural output.

The retained 2026-10-16 standalone preparation run passed those counts and strict actual-unit lint in both ADD_COMPARE_ONLY profiles. The portable installed target has not yet run; fixture identity does not inherit a new installed PASS. The runner bounds Icarus compilation to 30 seconds and runtime to 90 seconds, removes its own executable, and verifies actual source identities after execution.

This finite selector proof shares arbitrary arithmetic/count/mask carriers whose actual source equations are unchanged by the complete inverse. It is not an arithmetic-history, full-unit temporal or numerical ISA proof. Existing temporal/manual oracles must remain unchanged. A focused next cohort is `test-iu-shift-record`, `test-record-execution`, `test-core-record-logical`, `test-core-record-edges`, `test-core-add-flags` and `test-stage`, with the normal strict lint/spec gates. The optional proof adds no default-suite work. Temporal/public-cycle acceptance, aggregate CI and an attributed physical fit remain pending. No Fmax improvement is claimed.
