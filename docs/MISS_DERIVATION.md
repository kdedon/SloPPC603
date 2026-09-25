# Pure 32-bit miss derivation

`ppc_miss_derive` is a combinational foundation used by the opt-in 603e
software miss-entry path. It accepts a captured 32-bit effective address, its committed segment
descriptor, and a 32-bit SDR1 value. It has no state, request handshake,
exception entry, miss SPR write, or memory access. The local
PowerPC Programming Environments Manual (`MPCFPE.pdf`),
§§7.6.1.1.2, 7.6.1.3.2 and 7.6.1.4.2 (Figures 7-28, 7-30 and 7-32), supplies
the 32-bit SDR1 format, hash and PTEG address construction. The 603e manual
§§2.1.2.2–4 and 5.5.2.1.1–3 supplies the miss-register roles but defers
the PTEG algorithm to that Programming Environments Manual.

Verification: [MISS_DERIVATION_VERIFICATION.md](MISS_DERIVATION_VERIFICATION.md).

The interface is `ea_i[31:0]`, `sr_i[31:0]`, `sdr1_i[31:0]` and outputs
`valid_o`, `miss_page_o[31:0]`, `compare_o[31:0]`, `hash1_o[31:0]`, and
`hash2_o[31:0]`. All four data outputs are exactly zero when `valid_o=0`.
This is validation of inputs to the *derivation*, not a validation or
normalization of software's full-width SDR1 register write.

For a valid input, architectural SDR1 bits 0–15 are HTABORG (HDL
`SDR1[31:16]`), bits 16–22 are reserved (`[15:9]=0`), and bits 23–31 are
HTABMASK (`[8:0]`). HTABMASK must be a run of low-order ones, including zero
and all nine ones. If the mask has `k` ones, the low `k` HTABORG bits must be
zero, giving a table aligned to its `2^(16+k)`-byte size. Segment T must be
zero (`SR[31]=0` in HDL). Segment N is not rejected: it is relevant to
instruction permission, while a data miss may carry N=1.

In HDL bit numbering, the 19-bit primary hash is
`SR[18:0] XOR {3'b0, EA[27:12]}`; the secondary hash is its 19-bit one's
complement. The outputs are:

```text
miss_page = EA[31:0]
compare   = {1'b1, SR[23:0], 1'b0, EA[27:22]}
HASHx     = {SDR1[31:16], 16'b0}
          | ((hashx[18:10] & SDR1[8:0]) << 16)
          | (hashx[9:0] << 6)
```

Despite the retained `miss_page_o` port name, its value is the entire
accepted effective address, including byte offset. The 603e manual Table 5-9
explicitly calls IMISS/DMISS a 32-bit effective address, and its worked
failed-search handler copies DMISS to DAR. Figure 5-12's "effective page
address" caption does not specify low-bit truncation. Only the compare/hash
derivation ignores the byte offset.

`HASHx[5:0]` are zero; each is a 64-byte PTEG base address. The expression
keeps the upper seven HTABORG bits and ORs only mask-selected hash bits into
its lower nine bits. The compare word sets V, copies the 24-bit VSID, clears
H, and copies the six-bit API. These are candidate values only: no IMISS,
DMISS, ICMP, DCMP, HASH1 or HASH2 architectural register changes here.
The opt-in miss-entry integration uses the response-bound context of the
accepted oldest miss and samples committed SDR1 there. See
[EXCEPTION_TLB_MISS.md](EXCEPTION_TLB_MISS.md).

A focused oracle should use literal independent vectors for zero, partial and
full HTABMASK; changed VSID/page-index bits in both high and low hash regions;
primary versus complemented secondary addresses; nonzero byte offset and
SR.N; and each invalid case (reserved SDR1 bit, mask hole, misaligned base,
SR.T). Reset, retirement and cancellation tests belong to the later CPU state
and miss-entry slices, not this stateless unit.
