# Software PTEG search verification

`tb_compiled_table_search_firmware.sv` passed **299,206 checks over 5,140 retirements and 54,838 cycles**. An isolated mutation that removes the PTE R/C halfword write is rejected before TLB refill at cycle 30,602 with “TLB fill preceded exact PTE read and R/C write.” The harness runs the compiled 603e software miss handler against the integrated CPU, BAT, segment, TLB, and physical memory path. The harness supplies a 192 KiB byte RAM from `0xfff00000` through `0xfff2ffff` and loads only the boot image. Firmware stores every PTE into the physical table at `0xfff10000`; the harness does not preload TLB entries or PTEs. It checks fixed physical addresses and words independently of the handler and its `pte_before` snapshot.

The four events have these literal search outcomes:

| Event | Full miss EA | Search | PTE0 address | PTE1 before → after | Refill way |
| --- | --- | --- | --- | --- | --- |
| Instruction | `0x20000000` | Primary slot 7 | `0xfff19e38` | `0xfff06002 → 0xfff06102` (R) | 0 |
| Data load | `0x10008004` | Secondary slot 6 | `0xfff170f0` | `0xfff08002 → 0xfff08102` (R) | 0 |
| Data store | `0x10009008` | Primary slot 3 | `0xfff18f58` | `0xfff09002 → 0xfff09182` (R+C) | 0 |
| Resident C=0 store | `0x1000a00c` | Secondary slot 7 | `0xfff17078` | `0xfff0a002 → 0xfff0a182` (R+C) | 1 |

Each PTE0 scan address must advance by exactly eight bytes through the relevant primary or secondary group. The target PTE1 may be read once only after the required PTE0 comparisons. The handler's R-only `stb` must use strobe `0010`; store R+C `sth` must use `0011`, both at the target PTE1 word. The updated word must be present before the CPU offers its prepared `tlbli` or `tlbld` request. The harness compares all 128 words in eight PTEGs before the first miss, after each update, and at completion. Its fixed expected table includes decoys with wrong V, H, VSID, and API fields plus primary-group entries with the wrong H bit; no decoy may change.

Retirement checks require four precise response-bound miss capsules with full EAs, I/load/store/C=0 causes, and the C=0 matched way. Each successful refill must use the selected PTE's RPN, C, PP and bank; RFI then retries at the original faulting PC. Physical probe accesses must reach `0xfff06000`, `0xfff08004`, `0xfff09008`, and `0xfff0a00c`, with the final data words intact. The test also checks no terminal diagnostic, eight temporary-bank transitions, and a single success mailbox write. A failure stub writes a distinct non-success code.

`tb_core_tlb_miss.sv` separately checks the corrected full IMISS/DMISS values. Its byte-update phase uses an effective data address `0x10001235`: the router response capsule remains word-aligned at `0x10001234`, while architectural DMISS must read back the complete byte address, and the retried `lbzu` must update its base to `0x10001235`.

This profile covers successful software search and PTE R/C writeback. Its linker routes unexpected ordinary-fault conversions to the terminal diagnostic stub. The separate [table-fault profile](TABLE_FAULT_VERIFICATION.md) verifies those conversions with real ordinary vectors.

## Final shared-handler preservation gate

The expanded permission-aware handler preserves all four success cases:
5,152 retirements, 55,018 cycles, 300,164 checks. An isolated image replacing
`table_search_rc_write` (`sth`, physical `0xfff02880`) with `isync` is rejected
at cycle 30,694 before TLB fill because the exact PTE R/C write is absent.
The canonical ELF remains unchanged.
