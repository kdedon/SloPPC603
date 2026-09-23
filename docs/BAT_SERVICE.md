# Committed BAT register and translation service

`ppc_bat_service` owns both four-entry IBAT and DBAT banks and wraps the accepted
`ppc_bat_translate` with one serialized request/response interface. It closes
the selected-bank ownership gap for a standalone service. It does not connect
BAT SPR instructions, translation, or exceptions to `ppc_core`.

## Source and local policy

The local 603e manual is
`1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, MPC603EUM/AD, 11/97.
Figure 2-1 at PDF 81 / printed 2-3, visually reviewed, enumerates IBAT0U/L
through IBAT3U/L as SPRs 528–535 and DBAT0U/L through DBAT3U/L as 536–543.
Section 2.1.1 at PDF 83–84 / 2-5–2-6 places BAT registers in supervisor state.
Section 5.3, PDF 216 / 5-20, says BAT registers are not initialized by hardware
reset and warns against overlapping BAT areas, including with translation off.

The official [Programming Environments, MPCFPE/AD Rev.1](https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf)
corroborates the exact supervisor SPR mapping in Table 8-10, PDF 569 / 8-157
(read), and Table 8-15, PDF 586 / 8-174 (write). Chapter 2 introduction, PDF 63 /
2-1, permits reserved-bit writes but leaves readback of written ones undefined.
This service instead rejects such writes as an explicit local input restriction.
Source hash, BAT field/length/permission locators and the specific 603e IBAT G
versus generic PEM conflict are recorded in [BAT_TRANSLATION.md](BAT_TRANSLATION.md).

No source defines this service's transactional interface or atomic rejection
policy. Those are implementation choices:

- Synchronous reset zeroes all sixteen 32-bit storage registers and drops the
  response. This deterministic local invalid-bank initialization is **not** the
  physical 603e reset state. Software initialization requirements on silicon
  remain unchanged. Reset assertion immediately gates both valid/ready outputs;
  storage changes at the reset sampling edge.
- Each successful write updates exactly one addressed 32-bit half. The partner
  half, other entries and opposite bank remain unchanged. Readback returns the
  last accepted value exactly. Accepted reserved bits are always zero.
- All nonzero reserved-field writes are rejected, as are non-table upper BL
  masks and IBAT lower W=1. No reserved bits are silently masked. An inactive
  lower register may hold a base not aligned for its current upper BL; activation
  subsequently checks the complete pair. Inactive upper entries still require
  legal BL and zero reserved bits at this write interface.
- Before commit, a candidate write is substituted into a copy of the selected
  four-entry bank and checked by the existing translator's whole-bank validator.
  Active misaligned bases, intersecting effective ranges with shared privilege
  validity, and other translator configuration errors reject the write and
  preserve the entire old bank. Rejection is independent of requested IR/DR.
  This is stricter than software-visible `mtspr` behavior; it does not emulate
  intermediate invalid BAT states, hardware corruption or architectural faults.
- The supported reconfiguration sequence is: disable the old upper valid bits,
  write the lower half, then write a valid new upper half. A failed enable leaves
  the old inactive upper and the prepared lower half intact. Direct valid-to-valid
  updates are allowed if the resulting bank passes validation.

## Interface and ordering

There is one arbitrated request port. The caller selects exactly one operation
per transaction; no independent instruction/data request can bypass it.

| `req_kind_i` | Operation | Fields used |
|---:|---|---|
| 0 | Instruction translation | EA, IR, PR; internally selects IBAT |
| 1 | Data read translation | EA, DR, PR; internally selects DBAT |
| 2 | Data write translation | EA, DR, PR; internally selects DBAT |
| 3 | Committed BAT SPR read | SPR number, PR |
| 4 | Committed BAT SPR write | SPR number, write data, PR |
| 5–7 | Unsupported operation | No state change |

`req_spr_i` is the ordinary 10-bit architectural SPR number, **not** the split
bit-field encoding in an `mfspr`/`mtspr` instruction. CSR requests outside
528–543 return unsupported even in problem state. An in-range CSR request with
PR=1 returns privileged and cannot read or write bank contents. This interface
does not decide instruction-decode exception priority for arbitrary SPR opcodes.

Acceptance is `req_valid_i && req_ready_o`. A successful write commits once on
that edge; result consumption never reapplies it. The caller therefore supplies
already-committed writes, not speculative instructions. No external cancellation
input is provided. The response captures request kind, EA and SPR context even
when a particular field has no semantic use for that operation.

One registered response slot holds the complete result. While valid and not
ready, all payload bits remain fixed, all new requests stall, and no offered
write can change storage. On a ready edge, the next request may replace the old
response. That request observes the currently committed bank, including any
earlier accepted write. There is no same-edge multi-request read/write ambiguity.
Inputs for a stalled request must remain stable under ordinary valid/ready rules.

`rsp_valid_o` is the only response qualifier. Successful CSR reads return the
stored half in `rsp_data_o`; successful writes return zero data and no translation
flags. `rsp_privileged_o`, `rsp_unsupported_o`, and `rsp_write_rejected_o`
distinguish rejected service operations. A write rejection also sets local
configuration error; the invalid-entry mask identifies an invalid candidate or
the entry targeted by an invalid encoding. Overlap identifies a whole-bank
collision. These are diagnostics, not ISI/DSI/program exception events.

Translation results preserve the existing translator contract: real-mode bypass,
BAT hit/miss, protection/guarded/configuration diagnostics, index/match mask,
PA/WIMG/PP. PA is usable only with `rsp_allow_o`; a miss returns no identity
mapping. WIMG attributes remain metadata rather than implemented cache/bus
ordering. The valid bank invariant normally prevents configuration errors during
translation; diagnostics remain in the response for explicit contract reuse.

## Verification and reproduction

From `ppc603e`:

```sh
verilator --lint-only -Wall --top-module ppc_bat_service \
  rtl/ppc_bat_translate.sv rtl/ppc_bat_service.sv
verilator --binary --timing --assert -Wall --top-module tb_bat_service \
  rtl/ppc_bat_translate.sv rtl/ppc_bat_service.sv tb/tb_bat_service.sv \
  --Mdir /tmp/ppc-r38-bat-service
/tmp/ppc-r38-bat-service/Vtb_bat_service
```

`rtl/bat_service_files.f` is isolated from the existing CPU/translator lists.
The direct bench uses literal mappings and checks all sixteen SPRs, both banks
and all entries, exact partner preservation, privilege/unsupported outcomes,
candidate rejection and remapping, instruction/data protection and attributes,
disable/prepare/enable sequencing, offered writes behind a held translation,
turnover, and reset cancellation. The existing translator's exhaustive field
tests remain separate.

The optional `+VECTORS=file` accepts nine hexadecimal fields per transaction:

```text
kind EA SPR wdata IR DR PR stall_cycles expected137
```

The bench offers the next transaction while the current response stalls, checks
the entire current payload at every held edge, then accepts the next request
on response turnover. `stall_cycles` is bounded to 0–32. A nonempty corpus and
exact field widths/counts are required. The expected 137-bit response is:

| Bits | Contents |
|---|---|
| 136:134 / 133:102 / 101:92 | kind / EA / SPR echo |
| 91:60 / 59 / 58 / 57 | CSR read data / privileged / unsupported / write rejected |
| 56:48 | allow, bypass, hit, miss, PP fault, G fault, config error, invalid input, overlap |
| 47:44 / 43:40 / 39:38 | invalid entry / match / hit index |
| 37:6 / 5:2 / 1:0 | PA / WIMG / PP |

The parent-owned arithmetic/interval transaction generator provides an independent
expected bank and translation model. There is no TLB/page/segment state, MSR storage, core SPR decode,
context-synchronization instruction, precise exception delivery, timing-conformance
or FPGA-fit claim in this milestone.

## Measured acceptance

Final strict Verilator 5.020 lint/build passed without warnings. The direct bench
passed **540 checks**. The parent-owned `sim/tools/bat_service_vectors.py`
independently modeled storage, interval matching and physical base-plus-offset
translation and passed **57,950 transactions / 695,942 total bench checks**
against the frozen service binary. The corpus contains 45,295 translations,
3,627 successful writes, 6,616 reads, 452 privilege rejections, 1,795 unsupported
requests and 165 rejected writes. It exercises all twelve block sizes, both
banks and four entries, privilege/protection/validity/boundaries, independent
IR/DR settings, preserved state after rejected candidates, overlap/disjoint
privilege aliases, and deterministic malformed operation/SPR/write cases.

The canonical corpus path is `sim/build/bat-service/vectors.txt`; the initial
acceptance log is `/tmp/ppc-round38-bat-independent.log`. Expected observations
come from the parent-owned generator, not this bench or the RTL. Each next
transaction is offered while the preceding response is held for 0–5 cycles.
An injected expected-response mismatch was rejected by the actual comparison
path. Separate empty, malformed and excessive-stall files were also rejected,
with results in `/tmp/ppc-r38-bat-service/parser-negative-results.json`.
Regenerable top-level `*.gch` files were removed only from the owned
`/tmp/ppc-r38-bat-service` build directory; binaries and test evidence remain.

## Opt-in retirement-prepared runtime writes

`ENABLE_RUNTIME_BAT` adds request kind5 PREPARE_WRITE and the explicit
prepare-commit/abort plus held commit-ack interface. Validation matches kind4,
but successful preparation only reserves selector/data; the sole committed
bank changes on commit. Abort wins a same-edge preparation without withdrawing
its response. Full pin, ownership, reset and arbitration rules are frozen in
[RUNTIME_BAT_PROTOCOL.md](RUNTIME_BAT_PROTOCOL.md). Kind5 remains unsupported
when the parameter is zero; the original startup-write behavior is unchanged.
