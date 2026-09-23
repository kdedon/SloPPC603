# Response-bound page-miss diagnostics in the core

`ENABLE_PAGE_MISS_RESULTS=0` gates the abstract core and special lane. The integrated router and wrapper have the same opt-in parameter; the router additionally requires page translation. This is a diagnostic transport increment. It does not enter the 603e I/D miss vectors, set TGPR, write IMISS/DMISS/HASH state, search page tables, update a PTE changed bit, or retry a faulting access.

The router's existing instruction/data response handshake carries a 69-bit `page_miss_t` capsule alongside the typed cause. Its packed order is `{ea[31:0], sr[31:0], pr, ir, dr, write, way}`. These are request-time EA, committed segment descriptor, and PR/IR/DR/write context captured by the router. There is no second capsule handshake or live-context resampling. Generic transport errors, non-page faults, and idle responses carry zero. The core inputs are `imem_rsp_page_miss_i` and `dmem_rsp_page_miss_i`; the fetch unit receives `rsp_page_miss_i`.

The typed causes are `FETCH_PAGE_MISS=3`, `DATA_PAGE_MISS=2`, and `DATA_PAGE_CHANGED=3`. The changed code denotes a resident page whose store cannot proceed because C=0; it remains distinct from an absent mapping. An enabled instruction miss enters the instruction queue with its PC and capsule, bypasses instruction decode, allocates an illegal no-write diagnostic entry, and retires the same capsule. The fetch unit's existing one-outstanding redirect path consumes and discards a response from an old path before it reaches the queue.

An enabled data miss or changed response is accepted only by the serialized special lane that owns the outstanding memory request. The lane captures the typed cause and capsule in its result, marks the result diagnostic, and does not install any architectural state. A killed offered request drains its response without producing a result. The completion queue accepts only the matching active producer generation and rejects a result killed by an accepted redirect. For a matching typed result, it preserves the cause and capsule while clearing GPR, update-base, flag, and XER permissions and marking the retirement illegal. Transport errors and disabled/unknown typed responses retain the older generic illegal diagnostic with a zero capsule.

The capsule is intentionally not part of `uop_t`: fetch diagnostic allocation copies it directly from the instruction queue, and data completion carries it in the result packet. The completion record stores it only until retirement. The page fault status pins remain sticky observations, not event identity; a younger canceled fetch may update a sticky EA without changing the exact retired PC/capsule.

Verification should cover enabled and disabled profiles; held response stability; each typed instruction, load, store and C=0 store outcome; request-time SR/context versus later live changes; exact retirement PC, cause and capsule; zero destination/update/flag/memory effects; and both pre-response and same-edge cancellation. Architectural miss-entry state and software refill/retry require separate work.

The appended `way` is the sole matched way for C=0 stores and zero for true
misses. The data capsule follows the aligned physical request address; CPU
DMISS captures the matching LSU effective address, including byte offsets.
