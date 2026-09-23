# Serialized control flow and real-mode memory

This temporary milestone prioritizes executable programs before returning to the original integer-family queue. It adds a conservative control/memory lane that drains older work, allocates an ordinary tagged completion entry, and blocks younger dispatch until retirement or cancelled-response drain. It is functional bring-up, not a 603e BPU/LSU timing implementation.

## Implemented scope and sources

- `b`, `bc`: relative/absolute and link variants; `bclr`, `bcctr`: link variants. BO/BI conditions, CTR decrement/zero tests and old LR/CTR targets are implemented. LK updates LR even when a conditional branch is not taken. Prediction hints are accepted where valid, but prediction and folding are absent.
- `mflr`, `mfctr`, `mtlr`, `mtctr`: the SPR8/9 subset of `mfspr`/`mtspr`. Other SPR selectors remain unsupported by this implementation.
- `cmp`, `cmpl`, `cmpi`, `cmpli`: 32-bit comparisons to any BF-selected CR field, preserving all other fields and XER. Reserved bits and L=1 are rejected.
- `lbz`, `lhz`, `lha`, `lwz`, `stb`, `sth`, `stw`, plus their non-update indexed forms: aligned, uncached, big-endian transfers through an abstract data interface. Update, multiple/string, reservation, byte-reversed and floating-point memory forms remain unsupported.

Primary 603e UM encodings are Table A-22 (PDF384), A-13 (PDF381), A-14 (PDF382), A-26 (PDF385), XL form A-37 (PDF394), XFX form A-38 (PDF395), and SPR Figure2-1/descriptions (PDF81–82). Shared instruction semantics use tagged 601UM evidence: branches PDF575–578, BO Table3-25 PDF190–191, SPR moves PDF679/690, and scalar load/store instruction descriptions PDF639–759. These secondary sources are not timing oracles.

Valid BO values are 0–5, 8–13, 16–20; the gaps and 21–31 are reserved. BCCTR permits only 4, 5, 12, 13 and 20, because it cannot decrement its target register. XL bits15:11 and reserved Rc bits in X/XFX forms must be zero. Metadata retains these restrictions explicitly.

## State and ordering

Ordinary integer operations retain the reservation-station/IU path. The serialized lane reads committed operands after the completion queue and integer pipeline drain. Its third GPR read supplies store data independently of the address operands. No new speculative SPR or memory forwarding is claimed.

All operations still finish by completion slot and generation. Nongpr-writing instructions allocate completion entries without allocating GPR rename registers. BF is carried in the allocated retirement packet; the existing exact-tag flag owner protects comparison state. LR/CTR writes occur only on the matching retirement handshake. A taken branch redirects at commitment, using its own retained queue identity, and discards old sequential fetch traffic. An internal committing branch takes priority over an external test redirect; the external acceptance output reports only acceptance of that external request.

## Data interface

A request has valid/ready, write, aligned 32-bit word address, 32-bit write data and four byte enables. Big-endian byte offset zero uses enable bit3 and data bits31:24; offset three uses bit0 and bits7:0. Loads extract the addressed byte/halfword from the returned word; LHA sign-extends the selected halfword. Effective addresses wrap at 32 bits. rA=0 means a literal zero base, while indexed rB=0 and store/source r0 are ordinary register reads.

Every accepted request, including stores, receives one response with valid/ready, 32-bit data and an error bit. Response ready is asserted only after the request acceptance has been registered. A responder may produce an immediate response but must hold it until accepted. A store error acknowledgment must indicate that the store had no external effect; the core cannot undo a peripheral write.

Only one data obligation is outstanding. A held request cannot be withdrawn or changed. Killing a load before an offer cancels it locally; killing an already offered load retains the offer, then drains and discards the response, including any error. New instructions remain blocked until the old obligation drains. Repeated redirects may change the eventual fetch target without assigning an old response to new work.

## Store authorization and faults

A store waits at the serialized CQ head for `retire_ready_i` to authorize a latched reservation. Its request is offered only after that edge. Reservation authorizes the external memory effect and makes the store irrevocable through the later response and retirement handshake. Lowering ready afterward must not retract the request or permit cancellation. The final retirement handshake records completion; it is distinct from the earlier external-effect authorization. This is an explicit extension of the retirement-ready contract.

Misaligned halfword/word accesses produce a diagnostic before any data request. Error responses produce an ordered diagnostic without a load destination write. Killed errors produce no diagnostic. Faults still use the bootstrap halt mechanism: exception vectors, MSR/DAR/DSISR, translation, caches and physical 60x bus handling remain later work. Reset clears state and valid outputs; the environment must cancel its pre-reset memory obligations.

## Verification

The symbolic program generator emits 631 instruction words and an independent 579-retirement path. Its interpreter executes operation names and arguments rather than decoding those words. The core test passes 44,883 checks of exact PC/word, all 32 GPRs, full CR/XER/LR/CTR and byte-memory digest. It executes 31 loads, 22 stores, a counted accumulation loop, calls/returns, all comparison families and BF selectors, all AA/LK combinations, canonical BO condition/count combinations (including CTR zero/wrap), aligned old LR/CTR targets, signed loads, aliases, negative displacement and 32-bit address wrap. Backpressure includes 60 stalled data-request cycles and 151 stalled retirement cycles.

The edge fixture passes 799 checks: four misalignment diagnostics with no request, load/store error acknowledgments, cancelled held/accepted loads and coincident errors, repeated redirects during drain, store authorization/protection through request/response/retirement stalls, killed linking branches and a committing branch winning over an external redirect.

Compiled decoder validation passes 15,808 probes with 615 accepted, including BO/BI/reserved-XL combinations and all 1,024 SPR selectors for both move directions and Rc values. All 26 previous RTL targets, both new targets, core/wrapper lint and 120 Python tests pass. Independent review accepts the final bounded implementation. The matrix now has 90 reviewed entries: 80 implemented and 10 pending; 50 Appendix A source rows have bounded reconciliation and 176 retain full-mask transcription pending. The two SPR-move rows are reconciled only for selectors 8/9.

Faulted loads retain their rename allocation through terminal halt until reset. Resumable exceptions must reclaim it explicitly. No branch prediction/folding, pipelined LSU timing, update/split-unaligned forms, translation or FPGA closure is credited here.
