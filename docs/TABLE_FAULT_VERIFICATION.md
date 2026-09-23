# Compiled table-fault verification

`tb/tb_compiled_table_fault_firmware.sv` executes the pinned PPC603e-compiled `table-fault` image on `ppc_core_bat` with independent, delayed instruction/data RAM responses and retirement backpressure. The fixture starts in real mode, then lets software install SDR1, BAT and segment state; it does not preload any PTE or TLB entry. It uses the linked image's `tohost`, `fault_count`, and `fault_records` symbol addresses passed by the runner.

The oracle covers five fixed cases followed by all 16 `KEY × PP × {load,store}` combinations. A monotonic physical marker at `0xfff0b000` identifies the active case. For each case, the test requires exactly one typed architectural miss retirement and independently checks the saved EA, segment value, access type, way, and absence of faulting-instruction writes. Instruction and data search addresses are fixed expected physical PTEG addresses, including the secondary group for absent pages. The first three cases must scan all eight primary and eight secondary PTE0 slots without a PTE1 read. The guarded instruction must find primary slot 4; protected instruction primary slot 2; each matrix case primary slot 5. The physical data monitor enforces that PTE1 is read only after the selected PTE0 and that an allowed PTE R or R+C write precedes TLB fill.

The ten failure cases must issue no handler PTE write, no TLB fill, and no translated physical target access. For absent data pages, the physical-data monitor also rejects any request retaining the faulting EA; for the absent instruction page it rejects physical fetches outside the boot code. At each matched denial vector it checks that PTE1 R/C bits remain unchanged. On the ordinary vector fetch, the test checks DSI at `0xfff00300` or ISI at `0xfff00400`, entry MSR `0x40`, SRR0, exact SRR1 cause, and for DSI the full DAR and DSISR syndrome. The byte-load absent-page case checks DAR `0x1000c003`, retaining both byte-offset bits. All 32 normal GPRs and CR are compared to snapshots at the precise miss retirement. At the successful mailbox, the test also reads all ten six-word fault records from physical RAM and checks their marker, PC, SRR1, entry MSR, and DSI DAR/DSISR fields. The guarded instruction expects SRR1 `0x10000070`; instruction page protection expects `0x08000070`.

For the eleven allowed matrix cases, the test requires a single exact PTE1 update, one data TLB fill carrying the selected RPN, C, PP, VSID, and EA, and one translated physical target request. A denied matrix case must leave its PTE1 unchanged, including R/C bits. Physical instruction requests into the guarded `0xfff0d000` page or protected `0xfff0e000` page are rejected while those cases are active. The two instruction failure PTE1 words remain `0xfff0d00a` and `0xfff0e000`. The firmware independently checks all twelve PTEGs against CPU-written before snapshots and checks its returned load/store values. The harness additionally asserts response and retirement stability under backpressure, physical request ranges and WIMG, and zero capsule on ordinary retirements.

Run the canonical firmware profile with `make -C toolchain rtl-table-fault`. A strict standalone build of the new harness uses `verilator --lint-only --timing --assert -Wall` against `rtl/files.f`, `rtl/bat_service_files.f`, and `rtl/core_bat_files.f`.

The scope is software search and conversion of an architectural miss into an ordinary ISI/DSI. Hardware page-miss classification, miss-state retirement, and TLB fill are tested elsewhere; this fixture makes no claim about a general hardware page-table walker or arbitrary page-table formats.


## Accepted result

Final frozen harness: 21 cases, 21 misses, 10 ordinary vectors, 11 fills,
73,464 retirements, 782,367 cycles and 3,485,002 checks. An isolated image
changes `table_search_guarded_cause` at `0xfff02cfc` from `lis r2,0x1000`
to `lis r2,0x0800`. The independent ordinary-vector SRR1 check rejects it
at cycle 115,083, marker 4. The canonical ELF is unchanged.
