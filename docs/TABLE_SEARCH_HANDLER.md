# Bounded 603e software PTEG search handler

`toolchain/table-search-handler.S` supplies the three 603e miss vectors and a
real-mode refill routine for the compiled table-search fixture. It uses only
temporary r0–r3 while MSR[TGPR]=1. SPRG0–2 hold the full miss EA, automatic
compare word and event type across record generation and search. It does not
write normal GPR0–3, r4–r31, LR, CTR or XER before `rfi`. CR0 changes during
the search but is restored from SRR1 immediately before `rfi`.

The 603e User's Manual Table 5-9 (printed 5-34) states that IMISS/DMISS hold
the **full 32-bit effective address**. The handler records and passes that
address to `tlbli`/`tlbld`, including a nonzero byte offset; HASH1/HASH2 and
PTEG selection use its page bits. Section 5.5.2.2 (printed 5-38–39) describes
searching eight 8-byte PTEs at HASH1, then eight at HASH2, comparing each
PTE's first word with ICMP/DCMP. The handler compares the full H=0 automatic
word in the primary group and a **local** copy with H bit `0x40` set in the
secondary group. It leaves ICMP/DCMP H=0 because the current CPU TLB load
profile requires that seed form. The matching PTE's second word becomes RPA.

Before any page-table write, the handler checks that RPA-reserved bits 20–22
and 29 are zero. It then applies the 603e PP/KEY matrix using the miss-time
KEY saved in SRR1[19]. With KEY=0, PP=0/1/2 permits reads and writes while
PP=3 is read-only. With KEY=1, PP=0 denies all access, PP=1/3 is read-only,
and PP=2 permits reads and writes. A guarded instruction PTE takes an ISI
before its R/C bits change; data accesses may use guarded pages. This
software decision precedes both the physical PTE write and the TLB refill,
so a denied store cannot spuriously set C.

If neither eight-entry PTEG contains a match, the handler synthesizes an
ordinary ISI or DSI page-not-found cause (`0x40000000`). A matched but
prohibited access synthesizes protection (`0x08000000`); a guarded
instruction fetch synthesizes guarded ISI (`0x10000000`). The latter uses
the Programming Environments Manual Table 6-10 and the 603e User's Manual
Table 5-3; a worked guarded-handler line in UM §5.5.2.2 is inconsistent with
those architectural tables. DSI also copies the saved store bit into
DSISR[6] (`0x02000000`), writes the full DMISS EA to DAR, and preserves
SRR0. Both conversion paths retain only the saved MSR low 16 in SRR1,
restore CR0 from the old miss SRR1, clear MSR[TGPR] with `mtmsr`, and branch
immediately to the ordinary vector without touching a normal GPR. The
supported live mode is big-endian, so no little-endian DAR adjustment is
needed. Malformed RPA reserved bits and record overflow still take the
explicit diagnostic stub.

For an instruction or data load, the handler sets PTE1.R (`0x100`) and writes
only the R-containing byte at PTE1+2. For a data store, including a resident
C=0 hit, it sets R and C (`0x180`) and writes the trailing halfword at PTE1+2.
The fixture has one software writer, so this bounded halfword update preserves
but does not arbitrate concurrent changes to the lower WIMG/PP byte. The
manual's §5.5.3 (printed 5-50) cautions that individual R/C updates should
use byte writes; the handler uses a byte write for its R-only case. The
special memory lane retires the physical PTE write before the following
`sync`; the handler then writes updated PTE1 to RPA, executes `tlbli` or
`tlbld` in real mode with SRR1.WAY, restores CR0, and executes `rfi` to
retry the faulting access. No automatic hardware PTE search or R/C writeback
is claimed.

The compiled fixture places SDR1's table at physical `0xfff10000`, with
vectors at `0xfff01000`, `0xfff01100` and `0xfff01200`, main at
`0xfff02000`, and data at `0xfff08000`/`0xfff09000`/`0xfff0a000`. It
exercises an instruction primary hit, a data-load secondary hit, a data-store
primary hit, and a C=0 store secondary hit in way 1. The latter uses the
accepted matched-way miss capsule and SRR1.WAY to refill the same resident
way. Miss EAs `0x10008004`, `0x10009008`, and `0x1000a00c` prove that
DMISS retains nonzero offsets while HASH addresses still come from page
bits. Each entry begins with R=C=0; expected physical PTE1 updates are
`fff06102`, `fff08102`, `fff09182`, and `fff0a182` in that order.

The extended compiled fixture runs 21 sequential miss cases. Five cover absent
instruction/data pages, a guarded instruction PTE and instruction PP denial;
the remaining 16 exhaust KEY 0/1, PP 0–3 and data load/store. Every case
resets the four-entry miss-record scratch, while ten ordinary ISI/DSI entries
accumulate in `fault_records[16][6]` as `{case marker, SRR0, SRR1, DAR,
DSISR, entry MSR}`. The ordinary vectors live at physical `0xfff00300` and
`0xfff00400`; they observe the normal GPR bank, record the fault, and arrange
fixture-specific recovery. The shared handler itself leaves SRR0 unchanged
and performs no PTE write or TLB fill for any rejected access.

The handler exports `imiss_handler`, `dlmiss_handler`, `dsmiss_handler`,
`miss_load`, `miss_load_pc`, `miss_store`, `miss_store_pc`, and
`table_search_failure`, `table_search_r_write`,
`table_search_rc_write`, and `table_search_guarded_cause`. The write
labels name the actual physical PTE1 byte/halfword stores;
`table_search_guarded_cause` names the guarded-ISI cause instruction for
isolated negative controls. The per-case four-record ABI is
`miss_records[4][8]`, in the order `{EA, CMP, HASH1, HASH2, SRR0, SRR1, handler MSR, sequence}`;
`miss_count` advances once per entry. A fifth event or an unsupported RPA
encoding writes `0x8dff0001` to `tohost` and loops at the exported failure label. Missing and protected
PTEs now enter the ordinary exception vectors.
