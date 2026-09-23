# Standalone committed segment-register bank

`rtl/ppc_segment_registers.sv` implements sixteen committed 32-bit segment registers behind one registered valid/ready response slot. It stores descriptors and supports context snapshots; the bank itself does not decode CPU instructions, translate an effective address, access a page table, or raise an architectural exception. The opt-in CPU path uses this same bank for retirement-prepared segment CSR requests, as specified in [SEGMENT_RUNTIME_PROTOCOL.md](SEGMENT_RUNTIME_PROTOCOL.md). On a clean BAT miss, the opt-in page router also requests a kind-2 snapshot from this bank before looking up the existing TLB service; see [PAGE_PATH_PROTOCOL.md](PAGE_PATH_PROTOCOL.md).

The standalone compilation list is `rtl/segment_register_files.f`. The default profile retains the original direct service behavior; `ENABLE_RUNTIME_SEGMENT=1` enables kind 4 and its preparation/commit/abort/ack pins.

## Source boundary

The primary processor source is *MPC603e & EC603e RISC Microprocessors User's Manual* (MPC603EUM/AD, 11/97), local file `../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`.

- Section 1.3.1.9, PDF 59 / printed 1-19, defines sixteen 32-bit segment registers and the processor's instruction/data arrays.
- Section 2.3.6.3.2 and Table 2-41, PDF 123 / printed 2-45, state that the segment-register move forms operate independently of MSR.IR/DR.
- Table 5-6, PDF 214 / printed 5-18, identifies segment registers as supervisor MMU resources.
- Table 4-8, PDF 177 / printed 4-19, says their hard-reset contents are unknown. Table 4-9, PDF 178 / printed 4-20, does not initialize them on soft reset.
- Section 5.4.3.1 continuation, PDF 223 / printed 5-27, states that SRs have no valid bit and software must initialize them.

The architectural source is *PowerPC Microprocessor Family: The Programming Environments, Rev. 1*, local file `../MPCFPE.pdf`.

- Section 2.3.6, Figures 2-23/2-24 and Tables 2-17/2-18, PDFs 93–94 / printed 2-31–32, define the distinct T=0 and T=1 layouts.
- The Chapter 2 reserved-field rule, PDF 63 / printed 2-1, permits the selected deterministic zero readback policy for written T=0 reserved bits.

The detailed source transcription and later CPU-integration requirements remain in `docs/SEGMENT_REGISTER_CONTRACT.md`.

## Interface and acceptance

A request is accepted on `req_valid_i && req_ready_o`. With no prepared proposal or held acknowledgment, `req_ready_o` is high when the response slot is empty or its current response will be consumed on the same edge. A held response with `rsp_ready_i=0` blocks every following request, including a write. Runtime preparation and acknowledgment also reserve the slot. This guarantees that no later context mutation passes an unconsumed observation.

| `req_kind_i` | Operation | Selected index | PR handling | Response data / effect |
|---:|---|---|---|---|
| 0 | Read | indexed: `req_address_i[31:28]`; direct: `req_index_i` | PR=1 returns privileged error | Stored normalized descriptor; no mutation |
| 1 | Write | indexed: `req_address_i[31:28]`; direct: `req_index_i` | PR=1 returns privileged error and no write | Normalized accepted word; selected SR changes on request acceptance |
| 2 | Context snapshot | Always `req_address_i[31:28]` | Allowed for either PR value because this is an internal context observation | Stored normalized descriptor; no PA or translation claim |
| 3 | Unsupported | indexed/direct rule used by kinds 0/1 | PR is ignored | Data zero, unsupported error, no mutation |
| 4 | Prepared write, opt-in only | indexed/direct rule used by kind 1 | PR=1 returns privileged error and no proposal | Normalized proposal response; selected SR changes only on later commit |

The kind fields are three bits wide. Every response captures and holds the accepted request kind, selected index, and complete address. Error responses hold data zero. Privileged and unsupported are mutually exclusive: kinds 0/1 and enabled kind 4 may report privilege, kind 3 and disabled kind 4 report unsupported, and kind 2 reports neither. `req_indexed_i` and `req_index_i` have no effect on a snapshot selector. Kind 3 still uses them for deterministic index echo.

A snapshot contains only the stored descriptor, selected SR index, and accepted
effective address. The response does not echo PR, instruction/data access kind,
or read/write intent. The opt-in page router captures and retains that
request metadata alongside the accepted snapshot before submitting a TLB
lookup. The snapshot remains a context-storage boundary, not a complete
translation context or privilege decision by itself.

A successful legacy kind-1 write changes exactly one `sr_q` word on the accepting clock edge and returns the post-normalization word. A read or snapshot accepted on the same edge as consumption of a previous response observes the pre-edge bank. A following turnover write becomes visible to later requests after that edge. Enabled kind 4 instead stores only a private proposal at acceptance; the same committed SR bank changes exactly on `prepare_commit_i` after its response is consumed. Abort releases the proposal without changing the bank, and the registered acknowledgment remains held until consumed. The runtime router uses kind 4 for CPU writes.

## Descriptor policy

For T=0 (`req_data_i[31]=0`), the stored value is:

```text
req_data_i & 0xf0ffffff
```

This retains T, Ks, Kp, N and the 24-bit VSID while forcing HDL bits 27:24, manual reserved bits 4–7, to zero. A legal write containing ones in those reserved data bits is normalized; it is not rejected as a reserved instruction encoding.

For T=1 (`req_data_i[31]=1`), all 32 bits are stored and returned unchanged. T=1 changes the meaning of the remaining fields to an opaque direct-store descriptor. The 603e does not support direct-store accesses, so the opt-in page router classifies a snapshot containing T=1 as unsupported through the TLB lookup diagnostic without offering a physical address. This bank does not expose a VSID output and does not reinterpret the low 24 bits.

The bank has no architectural valid bits. `rst_ni=0` clears all entries and the response slot for deterministic standalone testing. That zero initialization is a local policy and is expressly different from the 603e hard-reset value, which is unknown. The interface has no soft-reset input and makes no soft-reset preservation claim.

## Verification

Strict lint command, run from `ppc603e/`:

```sh
verilator --lint-only -Wall --top-module ppc_segment_registers rtl/ppc_segment_registers.sv
```

The independent direct bench covers all sixteen selectors, direct and indexed
selection, address/index capture, T=0 normalization, opaque T=1 replacement,
privilege and unsupported outcomes, pre-edge read/snapshot behavior, held
response stability, blocked writes with changing live inputs, consume/accept
turnover, selected-entry isolation, T1-to-T0 replacement, and reset while a
response is held. It passed **566 checks over 111 accepted requests** with no
RTL finding.

The focused commands were:

```sh
verilator --binary --timing --assert -Wall \
  --top-module tb_segment_registers \
  --Mdir /tmp/ppc-r41-segment-tests \
  rtl/ppc_segment_registers.sv tb/tb_segment_registers.sv
/tmp/ppc-r41-segment-tests/Vtb_segment_registers
```

Validation used Verilator 5.020. Strict standalone lint and the independent
direct bench passed. These results validate the committed bank interface only;
they do not validate CPU instructions or address translation. The focused opt-in runtime service and router benches are documented in [SEGMENT_RUNTIME_PROTOCOL.md](SEGMENT_RUNTIME_PROTOCOL.md).

## Remaining work

The opt-in CPU path now decodes `mfsr`, `mfsrin`, `mtsr`, and `mtsrin` and routes their precise CSR requests to this bank; the standalone service bench alone does not prove those instruction outcomes. The opt-in router now performs page TLB submission after a clean BAT miss, capturing EA and the selected SR together and retaining that snapshot under stalls. T=1 direct-store access, page-table search, CPU VSID refill ownership, architectural invalidation instructions, miss SPRs/TGPRs and general software-managed translated execution remain unimplemented. The existing ISYNC refetch path and MSR.IR/DR behavior are dependencies for this bounded page-hit path, not substitutes for missing miss and refill behavior.
