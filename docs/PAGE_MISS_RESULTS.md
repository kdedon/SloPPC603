# Response-bound page miss results

Status: the original integrated diagnostic increment was accepted on
2026-09-23. The 69-bit matched-way extension has direct router evidence;
actual-core and compiled checks are pending. The diagnostic packet is also
used by a newer opt-in miss-entry path. This packet contract does not itself
search a page table, update PTE R/C bits, or retry an instruction.

`ENABLE_PAGE_MISS_RESULTS=0` is opt-in on the core, special lane, router and
integrated wrapper. The router requires page translation. A response carries
`page_miss_t`, a packed 69-bit snapshot in this exact order:
`{ea[31:0], sr[31:0], pr, ir, dr, write, way}`. `way` is the least
significant bit. Router ports use `logic [68:0]` to
keep its standalone source list independent of the core package. Core ports
use the package type. Names are `imem_rsp_page_miss_i/o` and
`dmem_rsp_page_miss_i/o`; fetch uses `rsp_page_miss_i`. This capsule travels
with the existing response valid/ready handshake; it has no independent event,
acknowledgement or sticky ownership. It is held stable under backpressure and
zero outside the matching typed response valid window.

Only an exact kind-0, correct-bank, captured-EA, well-formed page reply with a
single supported cause is eligible. A true miss requires miss=1, hit=0,
allow=0, match=0 and all other causes clear. A store changed-bit request requires data
store, hit=1, one-hot match, C=0, needs_changed=1, allow=0 and all other causes clear. Both require
captured SR.T=0; instruction misses additionally require SR.N=0. A clean
changed-bit result also requires the service's way to agree with its sole
one-hot matched entry. Only `DATA_PAGE_CHANGED` copies that matched way;
true instruction/data misses set `way=0`. This is the resident entry to
update, not a replacement-way recommendation for an absent mapping. Mismatched,
mixed and unsupported replies retain legacy diagnostic handling.

The typed selectors are `FETCH_PAGE_MISS=3`, `DATA_PAGE_MISS=2` and
`DATA_PAGE_CHANGED=3`. The latter distinguishes a resident page needing C work
from an absent mapping. Typed data responses set transport error to zero so
it cannot mask their cause. Typed instruction misses use the held fetch fault
response instead of the router's irreversible fatal state. Existing sticky
page diagnostics remain observations, not exception handshakes.

The router snapshots the exact accepted EA, direction and PR/IR/DR, plus the
committed SR selected for that translation. No later live input may replace
that context. Capsule outputs are zero outside a matching typed response.
The capsule field is named `page_miss` in fetch, result and retirement records.
Fetch packets carry the capsule through the existing instruction queue;
allocation copies it into the completion entry for an enabled fetch miss.
The special lane captures typed data cause and capsule only for its matching
live memory response. The completion queue preserves these diagnostic causes
and capsule at retirement, sets illegal, and suppresses all architectural
writes. Generic transport errors and unrelated faults retain zero capsules.
Disabled cores must ignore capsules and preserve legacy unsupported-fault
handling. Redirects discard wrong-path fetches and killed data replies through
the existing drain paths; stale producers cannot install metadata in reused
completion entries. A diagnostic retirement is not a 603e miss exception.

Acceptance checks include enabled/disabled classification, held-response stability,
request-time context, exact retired PC/capsule, no destination/update/flag or
memory side effects, and cancellation before and on the response-acceptance edge.
CPU-installed firmware mappings must exercise instruction/load/store misses
without fixture TLB preload. A C=0 store needs separate directed evidence.
Future HASH state may require an SDR1 snapshot or serialized SDR1 writes;
that architectural state is outside this diagnostic increment.

Accepted evidence: [independent verification](PAGE_MISS_RESULT_VERIFICATION.md)
and [compiled CPU-installed mappings](PAGE_MISS_FIRMWARE.md).
