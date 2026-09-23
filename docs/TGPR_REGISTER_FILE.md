# Opt-in temporary GPR bank

`ppc_regfile_gpr` adds `ENABLE_TGPR=0` and `tgpr_i`. With the option enabled,
`tgpr_i` selects a separate four-word TGPR bank for architectural register
indices r0–r3 on all three asynchronous reads and both retirement write
ports. With `tgpr_i=0`, r0–r3 use the existing normal bank. The normal
r0–r3 words remain unchanged while the temporary bank is selected. Both banks
persist across mode changes and clear to zero on this model's local reset;
that deterministic reset is not a 603e architectural reset guarantee. With
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

The existing two-write contract remains: simultaneous retirement writes must
have different architectural destination indices. Both writes select the bank
from the same `tgpr_i` value on that edge. The retained assertion rejects an
alias; there is no implicit write-port priority. A write to r0–r3 in TGPR mode
never changes the normal r0–r3 value, even when the other port writes r4–r31.

`tb_regfile_tgpr.sv` checks all read ports, both write paths, bank switching,
normal-bank preservation, r4/r31, disabled mode and local reset. Its alias
negative mode (`+ALIAS_COLLISION`) verifies the retained assertion. This unit
contract does not claim an architectural miss vector, TGPR entry, failed
lookup handler or `rfi` integration; those require separate core tests.
