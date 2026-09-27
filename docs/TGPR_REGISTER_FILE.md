# Opt-in temporary GPR bank

`ppc_regfile_gpr` adds `ENABLE_TGPR=0` and `tgpr_i`. With the option enabled,
`tgpr_i` selects a separate four-word TGPR bank for architectural register
indices r0–r3 on all three asynchronous reads and the retirement write
port. With `tgpr_i=0`, r0–r3 use the existing normal bank. The normal
r0–r3 words remain unchanged while the temporary bank is selected. Both banks
persist across mode changes and read zero after this model's local reset: the
four TGPR flops reset, and the normal bank (MLAB copies without reset) is
zeroed by a 32-edge walk of the write port, with `ready_o` low meanwhile.
That deterministic reset is not a 603e architectural reset guarantee. With
`ENABLE_TGPR=0`, `tgpr_i` has no effect and the original 32-word behavior is
preserved.

The 603e User's Manual Table 2-1 and Table 4-5 define MSR[TGPR] as manual
bit 14 (HDL `MSR[17]`), overlaying TGPR0–TGPR3 on GPR0–GPR3 for software
miss handlers. The manual calls accesses to r4–r31 while TGPR=1 undefined.
This bounded implementation continues to read and write those normal words;
software must not rely on that behavior as a 603e guarantee. A miss exception
sets TGPR and clears PR, EE, IR and DR (Table 4-16). The core must drive
`tgpr_i` from committed MSR state after draining older effects and discard
stale rename mappings when entering or leaving the temporary bank. The
register file does not generate miss entry or alter MSR. The manual explicitly
states that `rfi` clears TGPR; ordinary ISI/DSI entry after a failed table
search requires software to clear it first.

The file has one write port; the write selects the bank from `tgpr_i` on
that edge. A write to r0–r3 in TGPR mode never changes the normal r0–r3
value. The core defers an update load's base write by one edge and holds
dispatch meanwhile; MSR[TGPR] cannot change in that cycle.

`tb_regfile_tgpr.sv` checks all read ports, back-to-back writes, bank
switching, normal-bank preservation, r4/r31, disabled mode and local reset
and the 32-edge clear. This unit
contract does not claim an architectural miss vector, TGPR entry, failed
lookup handler or `rfi` integration; those require separate core tests.
