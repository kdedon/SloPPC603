# CPU execution through relocated BAT addresses

`make -C sim test-reference-bat` runs the all-168-form memory corpus on the
actual `ppc_core_bat` wrapper and compares every accepted retirement with the
original local DingusPPC handlers. The 102-field trace includes GPRs, CR, XER,
LR, CTR and all 64 words of the bounded big-endian data RAM.

The physical responder independently requires instruction addresses in
`0x40000000..0x4000ffff` and data addresses in `0x80001000..0x800010fc`.
An independent request monitor captures each accepted CPU effective address and
requires the exact literal EA-to-PA relocation and unchanged data payload.
It indexes its arrays only after checking these literal physical ranges,
alignment, and WIMG. Program effective addresses remain near zero and data
effective addresses remain `0x1000..0x10ff`. Consequently an untranslated
request cannot silently access the expected array element.

While the CPU is held reset, the bench installs an IBAT mapping to
`0x40000000` and a DBAT mapping to `0x80000000`. Both have PP=2; the data
mapping carries WIMG=2 and the instruction mapping WIMG=0. The bench holds
each setup acknowledgement and checks that execution cannot start early.
Start then captures local IR=DR=1, PR=0. This is the wrapper's explicit
startup interface, not execution of BAT SPR writes or a live MSR context.

Instruction requests, data requests/responses, and retirement encounter
independent backpressure. The bench checks stable offers, accepted ownership,
physical traffic counts and that architectural state changes only at accepted
retirement. The adapter compares all state snapshots, checks dynamic coverage
of every default implemented form, and requires three deliberately corrupted
GPR/RAM comparisons to fail at the named field.

`build/reference-bat/manifest.json` retains input/header/binary/trace hashes,
the reference revision and dirty status, tool versions, exact commands,
coverage and physical-transport counters. Inputs are frozen before building
and verified again after comparison. Regenerable compiler header caches are
removed only from this run's exact compiler directory after it finishes.

This lane verifies CPU execution through BAT routing, not an independent MMU
implementation inside DingusPPC: the original handlers use the existing flat
RAM backend. The literal physical-address checks supply the independent
translation observation. BAT denial/reset/redirect cases have separate direct
and actual-core tests in [CORE_BAT.md](CORE_BAT.md). The TLB remains a separate
service. There is no cache/60x attachment, live translation context, software
page-miss handler, self-modifying-code protocol, architectural fault delivery,
or cycle-conformance claim in this lane.

Round 39 acceptance matched **9,881 retirement snapshots** and all **168**
default forms. The physical responder accepted 9,922 instruction requests and
240 data requests, including 134 stores. It observed 41 data-request stall
cycles, 290 instruction-request stall cycles and 4,208 retirement stall cycles.
Three injected GPR/RAM corruptions were rejected. Speculative instruction
traffic may remain at the final recorded retirement, so these are coverage
counters rather than drained-system or performance measurements.
