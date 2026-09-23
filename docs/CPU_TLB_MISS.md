# CPU TLB miss exception entry

`ENABLE_TLB_MISS_EXCEPTIONS=0` is opt-in and requires supervisor exceptions,
live context, TGPR, SDR1, response-bound page-miss results and the CPU TLB
load instructions. It changes only well-formed typed page-miss results into
resumable exceptions. Existing transport, protection, guarded and malformed
page replies keep their prior behavior. The CPU does not search a page table.

The router's accepted-response capsule is 69 bits and carries
`{EA, SR, PR, IR, DR, write, way}`. The final way bit is a local response
snapshot, not a general replacement-policy state.
An instruction miss must have `EA==fault PC`, IR=1, write=0, SR.N=0 and
PR/IR/DR equal the committed mode. A data miss must have `EA` equal the
*aligned word address offered to the data router*, DR=1, and PR/IR/DR and
write direction equal the committed request. A changed-bit response is valid
only for a store and carries the unique matched DTLB way. A true instruction
or data miss must carry way=0; a nonzero way on either is diagnostic. Both
forms require MSR[TGPR]=0 and a valid result from the
pure 32-bit SDR1 miss-derive unit: SR.T=0, reserved SDR1 bits zero, a
contiguous HTABMASK and an aligned HTABORG. An invalid capsule or SDR1 value
remains a typed, no-effect diagnostic with its capsule at retirement; it
cannot update miss SPRs or enter a vector. SDR1 writes are fenced and allowed
only with IR=DR=0, so the committed SDR1 used at miss retirement cannot be
replaced behind an in-flight translated request.

The core allocates an instruction miss through the existing serialized fetch
exception lane, retaining its fetch cause and capsule. A recognized data miss
or changed-bit store travels with its exact held data response. Completion
suppresses destination GPR, update-form base, flag and value effects while
preserving the typed cause and capsule. A canceled or killed result does not
install miss state. Only the matching oldest retirement edge simultaneously
updates the selected miss registers and enters the exception state; no SPR is
written when a packet is merely offered, received or completed.

The 603e User's Manual §§4.5.12–14 and 5.5.2.1 (printed 4-33–35 and
5-35–38) define the three events. An instruction miss saves its instruction
PC in SRR0, writes IMISS (SPR 980) and ICMP (981), sets the I/D field in
SRR1, and redirects to vector `0x1000`. A data-load miss writes DMISS (976)
and DCMP (977) and redirects to `0x1100`; a data-store miss, including a
resident page needing its changed bit, redirects to `0x1200`. Both data forms
save the faulting instruction PC. HASH1 (978) and HASH2 (979) are shared
physical PTEG addresses for the last accepted I or D miss. Their calculation
and the compare word use the captured SR and EA, not later live segment
state. The automatic compare update replaces the prior software seed in the
corresponding bank. A true I/D miss selects WAY=0 deterministically. A C=0
store hit instead copies its matched DTLB way into SRR1.WAY, allowing a
software `tlbld` refill to replace that same resident entry. This is a local
matched-hit rule, not an implementation of LRU replacement.

The exception-state unit atomically saves CR0 into SRR1[31:28], the miss-time
segment key into SRR1[19] (`PR ? Kp : Ks`), instruction/data type into
SRR1[18], WAY into SRR1[17] and store type into SRR1[16], with the manual's
saved MSR fields. Exception entry switches to the temporary r0–r3 bank,
clears IR/DR and PR, and redirects through the selected high or low vector.
The data path holds its frontend/memory drain reservation until the redirect
is accepted. A handler can inspect the miss SPRs and compare state, write RPA,
execute `tlbld` or `tlbli`, restore CR0, then `rfi` to retry the faulting
access; `rfi` clears TGPR and restores the normal register view.

New DMISS, IMISS, HASH1 and HASH2 selectors are read-only through supervisor
`mfspr` (including the project's 603e `mftb` XO alias). `mtspr` for them is
illegal. The detailed 603e manual §5.5.2.1 says these table-search registers
*should only* be accessed with IR=DR=0. This core enforces that bounded mode
as a diagnostic for these four new reads. The existing software DCMP, ICMP
and RPA access policy is unchanged. Privilege rejection precedes completion
allocation for all implemented selectors.

The hardware does not search PTEGs, update R/C in memory or implement LRU.
The compiled [software search handler](TABLE_SEARCH_HANDLER.md) searches both
PTEGs and writes R/C before CPU-issued refill. Failed-search conversion and
permission coverage are tracked by its separate software acceptance gates.
A high-prefix image must reserve `0xfff01000`, `0xfff01100` and
`0xfff01200` for the three vectors rather than placing main at the first of
those addresses.

## Matched-way changed-bit repair

A clean C=0 store hit retains the TLB lookup's sole matched way in its held
response capsule. At oldest retirement that bit becomes SRR1.WAY. The handler
can set RPA.C=1 and execute `tlbld` with the unchanged SRR1.WAY to replace the
matching resident entry in either way; the service's cross-way duplicate guard
then does not reject it. A true miss still has no resident way and uses fixed
WAY=0. No matched-way value is inferred from current TLB state at exception
entry or after cancellation. The capsule and SRR1 transition are tied to the
same accepted request and exact retirement identity.

## Full effective miss address

UM Table 5-9 and Figure 5-12 specify all 32 bits of IMISS/DMISS. The earlier
page-offset truncation is corrected: IMISS retains the fault PC. DMISS uses
the held LSU effective address after verifying the router capsule matches
its aligned word request, thereby retaining byte/halfword offsets as well.
HASH and compare derivation still ignore offset bits as specified.
