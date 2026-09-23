# Bounded integer LSU update milestone

This milestone implements fourteen naturally aligned integer load/store update forms through the existing serialized real-mode memory lane. It provides architecturally atomic base update for the selected forms while preserving the existing external data-memory interface. It is a functional P10 milestone, not a pipelined LSU, cache, MMU, exception-vector, endian-complete, or timing implementation.

## Implemented forms

| Operation | D form | Indexed form | Memory result | Architectural writes |
|---|---|---|---|---|
| Load byte and zero with update | `lbzu` primary 35 | `lbzux` XO 119 | zero-extended byte | rD and rA |
| Load halfword and zero with update | `lhzu` primary 41 | `lhzux` XO 311 | zero-extended halfword | rD and rA |
| Load halfword algebraic with update | `lhau` primary 43 | `lhaux` XO 375 | sign-extended halfword | rD and rA |
| Load word and zero with update | `lwzu` primary 33 | `lwzux` XO 55 | 32-bit word | rD and rA |
| Store byte with update | `stbu` primary 39 | `stbux` XO 247 | low byte of old rS | memory and rA |
| Store halfword with update | `sthu` primary 45 | `sthux` XO 439 | low halfword of old rS | memory and rA |
| Store word with update | `stwu` primary 37 | `stwux` XO 183 | old rS | memory and rA |

D forms compute `EA = old(rA) + EXTS(SIMM16)`. Indexed forms compute `EA = old(rA) + old(rB)`, modulo 32 bits. Update forms do not apply the ordinary load/store `rA-or-zero` rule.

Every selected form requires `rA != 0`. Loads additionally require `rA != rD`. Indexed bit 31, conventionally named Rc in the generic X diagram, is reserved zero. Invalid forms retire as terminal diagnostics without a data-memory request or GPR write. Store aliases are legal: when `rS == rA`, the memory request contains old rS and rA receives EA only at successful retirement. `rA == rB` and other indexed source aliases likewise use the pre-instruction values.

## Atomic retirement model

`uop.mem_update` authorizes a second GPR effect when the completion entry is allocated. The entry records `update_write`, `update_gpr`, and a zeroed `update_value`; a producer supplies only `result.update_value`. Completion accepts that value only for the exact active generation and only when allocation authorized the update. A fault clears the normal GPR and update permissions and both payloads.

The special lane returns EA as the update value after a successful memory acknowledgement. The architectural GPR file has two commit ports driven from one accepted completion retirement:

- A load update writes the loaded value to rD and EA to rA on the same edge.
- A store update writes EA to rA only after the externally acknowledged store reaches accepted retirement.
- A stalled finished packet changes neither destination.
- A memory error or alignment diagnostic changes neither destination.
- An accepted cut that kills an unfinished load suppresses both writes; an already offered request remains stable until accepted and its reply is drained and discarded.
- A store becomes irrevocable after retirement authorization is latched and before its first external offer. Its base changes only at final retirement.

This implementation serializes every special operation: dispatch requires an empty completion queue and idle normal execution, and younger dispatch remains blocked through special retirement. Therefore an update instruction has no younger speculative consumer while its base is absent from the rename map. This justifies the bounded architectural second write without adding the 603e's second speculative GPR rename destination. The primary manual separately identifies load update as consuming two GPR destinations in the real completion machinery; that timing/resource behavior remains unimplemented.

## External memory and fault boundary

The data-memory contract is unchanged: one request with `valid/ready`, aligned 32-bit word address, 32-bit data and four byte strobes, followed by one response acknowledgement. Offset zero maps to the most significant byte and strobe bit 3. Byte accesses accept every offset; halfword and word accesses require natural alignment. Misaligned selected operations produce a terminal diagnostic before any request.

`dmem_rsp_error_i` is a bounded terminal diagnostic input. For a load it suppresses rD and rA. For a store it suppresses rA, although the external target may already have observed the request; the interface does not describe rollback. Reset cancels the modeled memory environment and architecture state. Resumable DSI/alignment exception state, DAR/DSISR/SRR updates, cacheability, translation and exception priority are outside this milestone.

## Sources and source limits

The primary MPC603e/EC603e manual supplies these anchors:

- Section 2.3.4.3.3-2.3.4.3.4, PDF pages 107-109, printed 2-29 through 2-31: load/store update behavior and old-rS ordering for `rS == rA`.
- Appendix A.1, PDF pages 364-367, printed A-4 through A-7: the fourteen opcode/XO rows and fixed-zero indexed bit.
- Tables A-13 and A-14, PDF pages 381-382, printed A-21 through A-22: LSU function and form grouping.
- Section 6.6, PDF page 267, printed 6-21: load update requires two GPR destinations in the implementation completion resources.
- Table 6-6, PDF pages 274-275, printed 6-28 through 6-29: selected rows are `2:1`; the serialized scaffold does not implement this timing.

The local Programming Environments Manual is absent. Tagged secondary MPC601UM per-instruction pages supply shared semantics and explicitly identify the PowerPC invalid forms: PDFs 640/641 (`lbzu/lbzux`), 652/653 (`lhau/lhaux`), 657/658 (`lhzu/lhzux`), 668/669 (`lwzu/lwzux`), 735/736 (`stbu/stbux`), 748/749 (`sthu/sthux`), and 757/758 (`stwu/stwux`). The 601 executes some invalid PowerPC aliases for POWER compatibility; this implementation follows the stated PowerPC rules and rejects them.

## Executable evidence

The focused checks are:

```sh
cd /home/kevin/git/ppc/ppc603e/sim
make test-lsu-update-decode
make test-completion-update
make test-lsu-update-edges
```

The decode bench checks all fourteen exact forms, D/indexed controls, sign and size selection, legal store/source aliases, load `rA == rD`, all `rA == 0` cases, and indexed reserved-bit rejection. The completion bench checks producer payload authorization, successful dual payload capture, illegal allocation normalization, and fault masking. The actual-core edge bench checks atomic load dual retirement, held request and retirement backpressure, rejected cuts of finished heads, load fault, misalignment before request, killed offered-load drain, old-rS store alias behavior, store irrevocability, and store-error base suppression.

The independent full-core program also exercises all fourteen forms with dependent post-update consumers, negative/wrapping displacements, byte lanes, indexed aliases, and both direct and pin-bus memory models. That broader program is maintained by the integration owner.

## Remaining P10 work

- Replace serialized special scheduling with a real LSU reservation/pipeline and two-destination speculative rename allocation.
- Implement cache/MMU/translation, complete endian steering, exception state and priority, and resumable faults.
- Reconcile PID7v misalignment behavior and implement supported split accesses rather than the current natural-alignment diagnostic boundary.
- Add multiple, string, reservation, floating-point and other update-addressing families.
- Meet and measure the source timing/resource rules; no timing-closure claim follows from these functional checks.
