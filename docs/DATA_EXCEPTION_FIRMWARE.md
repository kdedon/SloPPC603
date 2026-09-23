# Compiled DSI acceptance

The pinned offline toolchain builds `toolchain/dsi-smoke.c` and its assembly
handler. Initial simulation acceptance passed on 2026-09-22:
**8 denied loads, 4 denied stores, 30 BAT writes, 1,066 retirements,
133 physical reads, 120 physical writes, 12,302 cycles.**

Firmware installs all required mappings through CPU SPR accesses. Four loops
each skip a denied update load, skip a read-only update store, then repair a
denied load's BAT permissions in the handler and retry the same instruction.
The handler records exact DAR/DSISR/SRR0/SRR1 and entry MSR. C checks that skipped
faults leave the load destination and update base unchanged, denied stores
leave memory unchanged, and a successful retry updates its base exactly once.

The independent physical responder checks that only initialization and the final
permitted store reach the protected word. The trace requires twelve supported
non-illegal data-fault retirements without GPR/update writes and 26 IR/DR context
transitions. No harness BAT programming is used. Responses and retirements are
delayed. This workload establishes high-IP handling; low-IP and cancellation
cases are separate directed tests. Page misses, cache/60x composition and
resumable transport errors remain outside this slice.

All seven prior ELF workloads also passed against the changed RTL: basic cached
BE, alignment, fetch fault, live context, IRQ, timer/XER and runtime BAT. Their
ELF artifacts were reused; the DSI artifact was newly compiled. No FPGA fit ran.

## Negative control

A temporary copy of the generated memory image changed the expected load DSISR
constant at image offset `0x11b0`. The original instruction bytes `3d 40 08 00`
were asserted before replacing the last byte with `01`, changing the expected
syndrome from `0x08000000` to `0x08010000`. DUT sources and the original ELF were
unchanged. The simulator failed with SIGABRT at cycle 2,452 and the exact
`firmware failure mailbox=83000001` diagnostic, not a timeout.

Local logs are `/tmp/ppc-dsi-firmware.log`, `/tmp/ppc-dsi-old-firmware.log` and
`/tmp/ppc-dsi-negative.log`. These are temporary convenience artifacts. Commands
are in [the toolchain README](../toolchain/README.md); final integration evidence
is in [DATA_EXCEPTION_VERIFICATION.md](DATA_EXCEPTION_VERIFICATION.md).

## Initial passing input hashes

| Input | SHA256 |
| --- | --- |
| `rtl/ppc_pkg.sv` | `df4829f0cbced8cb1c810084dfe171c70e9bebd92d50b458ba58a3e6ed654953` |
| `rtl/ppc_completion.sv` | `6ad2a67652a1bd8aa87ec2969eca96e926f3689b8c1c8cb1850d5013326c6618` |
| `rtl/ppc_core.sv` | `105e5382618b2230e1c2875d0b639ff14aa7ec70a319647374ee771252dccab5` |
| `rtl/ppc_special.sv` | `ae23bffee2c8d596bf4f6d43304820cea8b719b4508cd97998b760951e9eed9c` |
| `rtl/ppc_exception_state.sv` | `4045b83b66973654dda11bcf102de71f21c215ef0edc24b4fc54f3ac0624cbd2` |
| `rtl/ppc_bat_memory_router.sv` | `3c41c6f7f100992f0b0d47d3c9d5670ddc8e5ba23ba16f3d552d53d17e244b4a` |
| `rtl/ppc_core_bat.sv` | `e2fd2058237e3b386543b259a55653dd01330f3a9446306a7bb3e9b8d8341905` |
| `tb/tb_compiled_dsi_firmware.sv` | `2b0c38ca99f22906c309d0ecd66335acce7e40ca1c349dfe5a00df1eed75d321` |
| `toolchain/dsi-smoke.c` | `6c62798e39c267db7d1eaeba74b3e99c3349970c35795608b1938e3529d01c91` |
| `toolchain/dsi-handler.S` | `84417d9f4db79833007f8ce412e59288f5657fb882aaf78766b6555d6499cd43` |
| `toolchain/build/dsi/smoke.elf` | `f7b24e0d2314b6b414a6aa69986ec86c5522924bba0d97efb1acd5fba588b4ab` |
