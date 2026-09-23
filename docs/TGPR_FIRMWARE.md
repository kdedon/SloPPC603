# Compiled temporary-register bank acceptance

The pinned compiler builds `tgpr-smoke.c` and `tgpr-probe.S`. The workload
uses only r0–r3 while TGPR is active, keeps normal registers distinct from
temporary values, and verifies persistence across two visits. It deliberately
sets saved SRR1 bit 17 before RFI and checks that TGPR nevertheless clears.
SPRG0/1 preserve the ABI's stack/TOC values; SPRG3 records handler failures.

The delayed-memory compiled wrapper passes 109 retirements in 1,078 cycles:
four bank changes, three MTMSRs and two RFIs (including bootstrap). The bench
checks serialization at each bank change and final mailbox retirement. An
isolated image omitting the first MTMSR fails at cycle 709 with mailbox
`8c000001`; the canonical image is unchanged. Automatic miss entry is a
separate acceptance gate.
