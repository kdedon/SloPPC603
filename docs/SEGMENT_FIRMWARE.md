# Compiled segment-register acceptance — 2026-09-22

The `segment` workload exercises the CPU-owned bank with all four management
instructions. It initializes BAT identity mappings itself, writes all sixteen
SRs with indexed forms in real mode, reads them directly, enables IR/DR, writes
each directly and reads each with indexed forms. Index-address low bits vary
independently. T=0 reserved bits clear; T=1 words remain opaque. Additional probes
cover source/index and destination/index aliases and ordinary GPR0 operands.

An external interrupt and DEC request remain pending while EE is clear across
a final SR write. Enabling EE takes EXT followed by DEC, with exact resume PC,
entry MSR and saved MSR checks. The bank survives both handlers and return to
real mode. Software includes ISYNC around updates. Segment contents do not yet
participate in address translation: this workload uses BAT hits throughout.

The acceptance harness applies independent instruction/data delays and retirement
backpressure. It requires 36 retired SR writes, 38 SR reads, four CPU BAT writes,
one EXT, one DEC, six IR/DR transitions, success mailbox retirement and transport
drain. The positive run passed 830 retirements, 15 reads, 35 writes and 9,271 cycles.

Reproduce using the pinned offline compiler image described in the toolchain
README, then from the project root:

```sh
make -C toolchain segment
python3 toolchain/run-rtl-smoke.py --profile segment --elf toolchain/build/segment/smoke.elf --build-dir toolchain/build/rtl-segment
```

Negative control: assert image bytes at offset `0x1070` equal `2c093400`, then
change the final byte to `01`. This changes the SR0 readback expectation without
changing its write. The simulator rejects the image with failure mailbox
`84000000` at cycle 3,479 (SIGABRT). Verify original bytes before reusing the offset
with another compiler/build. Local logs: `/tmp/ppc-segment-firmware.log` and
`/tmp/ppc-segment-negative.log`; generated files and temporary logs are not durable
CI storage. No page translation, refill, cache/bus composition or timing claim
is implied.
