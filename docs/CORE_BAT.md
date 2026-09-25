# Startup BAT routing for the actual core

`ppc_core_bat` combines the default-profile `ppc_core` with
`ppc_bat_memory_router` and the committed `ppc_bat_service`. It provides a
bounded integration path from the core's effective instruction and data
addresses to separate abstract physical memory ports. It is a local startup
and verification facility, not an implementation of PowerPC MSR/BAT SPR
instructions, segment translation, TLB lookup, or architectural ISI/DSI
delivery.

## Source boundary

The translation, register, and protection rules are inherited unchanged from
[BAT_TRANSLATION.md](BAT_TRANSLATION.md) and
[BAT_SERVICE.md](BAT_SERVICE.md). Their primary 603e sources are the local
`1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, especially Table 5-1 at
PDF 198 / printed 5-2, the translation flow and BAT lookup description at PDF
207–208 / 5-11–5-12, Table 5-3 at PDF 211 / 5-15, and the real-mode and BAT
programming discussion at PDF 216 / 5-20. The 32-bit BAT formats, sizes, and
permissions come from the official Programming Environments manual at PDF
321–329 / printed 7-33–7-41 as recorded in those documents.

The manuals define architectural registers and address translation. They do
not define this wrapper's setup/start handshake, serialized routing policy,
sticky diagnostics, or transport-fatal response. Those are explicit local
integration choices.

## Setup and fixed context

Hard reset places the wrapper in setup, holds the CPU in reset, clears the BAT
service's deterministic local bank state, and clears all wrapper diagnostics.
The `bat_write_*` port then programs ordinary BAT SPR numbers 528–543 through
the committed service. Each response must be consumed before another write or
start. Rejected, unsupported, overlapping, malformed, or reserved-field writes
are atomic and do not modify the committed bank.

An accepted `start_valid_i` captures `start_ir_i`, `start_dr_i`, and
`start_pr_i`, raises `running_o`, and releases the CPU from reset. The context
and all BAT storage remain locked until the next hard reset. A start cannot
overtake an offered setup write or a held setup response. This fixed context is
not live MSR state. In particular, this wrapper deliberately exposes no
supervisor-exception option: an architectural `rfi` could otherwise change the
CPU's MSR without changing the captured translation context.

The supported programming sequence is local test/startup control. CPU
`mfspr`/`mtspr`, HID0 controls, context synchronization, and software BAT
updates while running remain outside this milestone.

## Request routing

Instruction and data requests use their existing core valid/ready payloads.
The router accepts at most one request, captures its complete effective-address
and data payload, obtains one held BAT-service result, then issues one physical
request. It routes the eventual physical response only to that captured owner.
Payload changes after upstream acceptance cannot alter the translation or
physical transaction.

When instruction and data requests arrive together, selection alternates after
each accepted owner; reset history selects instruction first. Serialization is
a throughput limitation, but gives a simple starvation-free boundary for two
continuously offered requesters. A new owner is not accepted until the old
physical response or local data-fault response is consumed.

`IR=0` or `DR=0` uses the source-defined real-mode bypass: physical address
equals effective address, instruction WIMG is `0001`, and data WIMG is `0011`.
Translated accesses expose the selected BAT's WIMG bits unchanged. These bits
are metadata only; this wrapper does not implement cache selection, guarded
ordering, coherency, or bus pin attributes.

An accepted instruction fetch remains owned through its physical response even
if the CPU accepts an external redirect meanwhile. The CPU fetch unit consumes
and discards that old-path response before issuing the redirected fetch. The
router therefore neither cancels nor fabricates a response across redirects.

## Fault and error behavior

A denied data translation issues no physical request. It returns the existing
abstract data error response and records the translation owner, EA, and cause.
A denied instruction translation also issues no physical request, records the
translation cause, and enters a reset-only transport-fatal state because the
current fetch interface has no instruction-error input. `halted_o` combines
that fatal state with the CPU's ordinary halt indication. This is a diagnostic
stop, not a precise architectural exception.

A physical instruction response with its error bit set is consumed locally,
raises sticky `pimem_error_o`, and enters the same transport-fatal state without
presenting a fabricated instruction to the CPU. It does not rewrite an earlier
translation-fault record. Physical data errors pass through the abstract data
response and do not create a translation fault.

Translation fault fields record the most recent denied translation until
reset. The service's startup validator currently rejects an active guarded
IBAT configuration, so the accepted integration profile tests that condition
as a configuration-write rejection rather than claiming a reachable runtime
guarded-fetch fault. BAT misses do not fall through to segment or page
translation. No physical request is permitted after a denied translation.

## Files and ports

`rtl/core_bat_files.f` lists the router followed by the actual-core wrapper.
Builds also need the ordinary CPU list `rtl/files.f` and the service list
`rtl/bat_service_files.f`. The standalone router test needs only the service
list, `rtl/ppc_bat_memory_router.sv`, and its bench.

The physical instruction port carries a 32-bit PA and four WIMG bits with a
read response containing instruction plus error. The physical data port carries
PA, write direction, 32-bit write data, four byte strobes, WIMG, and a held
read/error response. No bus protocol, cache line, MMU timing, or memory ordering
is implied by these abstract channels.

## Verification

From `sim/`, the focused checks are:

```sh
verilator --lint-only -Wall --top-module ppc_bat_memory_router \
  -f ../rtl/bat_service_files.f ../rtl/ppc_bat_memory_router.sv
verilator --lint-only -Wall --top-module ppc_core_bat \
  -f ../rtl/files.f -f ../rtl/bat_service_files.f \
  -f ../rtl/core_bat_files.f
verilator --binary --timing --assert -Wall \
  --top-module tb_bat_memory_router \
  --Mdir ../build/ppc-r39-bat-core-router \
  -f ../rtl/bat_service_files.f ../rtl/ppc_bat_memory_router.sv \
  ../tb/tb_bat_memory_router.sv
../build/ppc-r39-bat-core-router/Vtb_bat_memory_router
verilator --binary --timing --assert -Wall --top-module tb_core_bat \
  --Mdir ../build/ppc-r39-bat-core-cpu \
  -f ../rtl/files.f -f ../rtl/bat_service_files.f \
  -f ../rtl/core_bat_files.f ../tb/tb_core_bat.sv
../build/ppc-r39-bat-core-cpu/Vtb_core_bat
```

The direct router bench passes **230 checks**. It covers held and rejected setup,
context locking, simultaneous instruction/data fairness, accepted-payload
capture, translated PA/WIMG, real-mode bypass, protection denial without a
physical request, permitted access, guarded-IBAT configuration rejection,
instruction miss, and separation of physical-instruction error from a retained
translation diagnostic.

The actual-core bench passes **330 checks** with nine physical instruction and
three physical data transactions, including one write and three retirement
backpressure cycles. It executes a relocated load/add/store/load program through
IBAT EA `0x00000000` to PA `0x40000000` and DBAT EA `0x00000000` to PA
`0x80000000`. It also holds an accepted wrong-path physical fetch across an
accepted redirect and verifies the old instruction never retires, exercises
real-mode fetch bypass, and proves an empty translated IBAT halts locally
without physical activity.

These benches do not claim a full MMU, architectural fault recovery, dynamic
context changes, downstream WIMG behavior, cache integration, or physical
603e timing.
