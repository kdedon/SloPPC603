# CPU SDR1 register foundation

`ENABLE_SDR1=0` is an opt-in CPU feature requiring live supervisor context. It
is independent of the CPU TLB load, invalidate, segment-register and BAT
features. The core recognizes supervisor `mfspr`/`mtspr` selector 25; the
project's existing 603e `mftb`/`mfspr` XO alias policy also applies to this
implemented selector. A problem-state access becomes a program-privilege
exception before completion allocation, with no SDR1 access or write effect.
With the feature disabled, selector 25 remains an illegal instruction.

A local 32-bit SDR1 register resets to zero. An allowed read samples the
committed value, including reserved fields, and follows the normal GPR-result
retirement and cancellation path. A write captures the old source GPR value,
then fences new frontend traffic and drains the core's prior fetch and data
responses. It changes SDR1 only at the matching retirement edge. The
committed write then takes the existing context-install handshake and redirects
to `PC+4` to refetch subsequent instructions. A canceled write, including a
same-edge recovery cut before retirement, leaves SDR1 unchanged; after the
retirement edge the write and its refetch are irrevocable. The core does not
alter MSR or the router's translation context on this path.

The Programming Environments Manual, Rev. 1, Table 2-22 and its notes
(printed 2-42), says altering SDR1 while MSR[IR] or MSR[DR] is one has
undefined results. This bounded core reports such a write as a diagnostic
fault and does not change SDR1. Reads are allowed in otherwise supported
modes. The same source requires a `sync` before `mtspr SDR1` and a
context-synchronizing operation afterward: the former protects page-table R/C
updates, and the latter orders subsequent translated accesses. The core's
fence/drain/refetch gives the needed ordering for its modeled outstanding
requests. Automatic page-table search and R/C memory writeback are not yet
implemented, so this increment does not claim their synchronization behavior.

The 32-bit SDR1 format is in that manual's §7.6.1.1.2, Figure 7-28 and
Table 7-25 (printed 7-66–67): HTABORG occupies architectural bits 0–15,
bits 16–22 are reserved, and HTABMASK occupies bits 23–31. Software writes
and reads retain all 32 bits without masking. The separate pure miss-derive
unit validates the format when deriving PTEG addresses; no automatic miss
SPR capture or architectural TLB miss entry uses SDR1 in this increment.

Acceptance requires feature-off decode, literal selector and XO-alias decode,
full-width reset/read/write roundtrips, problem-state rejection before
allocation, translated-write diagnostic with zero mutation, held retirement,
precommit cancellation, drain before update, irrevocable committed refetch at
`PC+4`, and preservation of unrelated MMU behavior.
