# P13b/P13c/P13d executable reference lanes

The isolated runner executes original DingusPPC instruction handlers and compares their architectural state with the actual `ppc_core` after every retirement. The v1 lane exercises all 140 currently implemented non-memory decode entries. The separately selected v2 lane retains that corpus and adds all 28 aligned scalar memory entries, comparing full flat RAM as well as architectural registers. It does not replace the accepted CSV parser. This closes bounded executable-reference milestones, not full P13 or whole-CPU differential verification.

Seeded mixed-program stress lane: [REFERENCE_STRESS.md](REFERENCE_STRESS.md).

## Reproduce

From the repository root:

```sh
python3 sim/cosim/run_reference.py \
  --build-dir build/ppc603e-reference-build
python3 -m unittest discover -s sim/cosim -p 'test_*.py'
```

Requirements are Python 3 standard library, Git, GCC with C++20, Verilator and its normal C++ build tools. The script uses argument arrays, compiles the unmodified local reference source, reads the canonical `rtl/files.f`, and builds only `tb_core_reference` in the isolated directory. It requires no DingusPPC machine build, SDL2, Cubeb, Capstone, network access, ROM or externally installed emulator. `--reference` selects another local reference checkout; `--model` accepts only `MPC603EV` (default) or `MPC603E`.

The underlying reference compile is:

```sh
g++ -std=c++20 -O2 -fwrapv -flto -ffunction-sections -fdata-sections \
  -DSUPPORTS_PPC_LITTLE_ENDIAN_MODE=0 \
  -DSUPPORTS_MEMORY_CTRL_ENDIAN_MODE=0 \
  -I../dingusppc -I../dingusppc/thirdparty/loguru \
  sim/cosim/reference_runner.cpp \
  ../dingusppc/cpu/ppc/ppcopcodes.cpp \
  -Wl,--gc-sections -o build/ppc603e-reference-build/reference_runner
```

`-fwrapv` explicitly constrains signed addition/subtraction/multiplication overflow in the compiler configuration. Most selected arithmetic handlers calculate with `uint32_t` (for example `ppcopcodes.cpp:126–328` and `:411–427`); `-fwrapv` is an additional build policy, not a claim that it repairs arbitrary undefined C++. C++20 is required, including its signed-shift semantics. The selected corpus passes with this configuration. No sanitizer or portability certification is claimed.

To run a separate reference program, supply one bare 1–8-digit hexadecimal instruction word per line:

```sh
build/ppc603e-reference-build/reference_runner program.hex MPC603EV > expected.txt
python3 sim/cosim/compare_state.py expected.txt actual.txt
```

The reference exits 2 for unsupported/reserved instructions, unknown models, malformed/empty input, a branch outside the image, undefined-result division, or exceeding 100,000 executed instructions. Every image word is checked for encoding legality before execution, including unreachable words. Immediately before an executed DIVW/DIVWU handler, the adapter also checks the actual current source registers: all zero divisors and signed `0x80000000 / 0xffffffff` are rejected, for every OE/Rc form. These are valid instruction encodings with undefined destination/CR results; they are classified as an oracle gap, not a masked architectural comparison or illegal opcode. Unexecuted exceptional operands have no dynamic effect. Exit at `PC == image_size_bytes` is the only normal termination. A runtime error can leave partial stdout: callers must check the exit status. There is no illegal sentinel or architecture-exception interpretation. The acceptance script checks subprocess success before reading output and removes any prior success manifest before starting a new run.

## Independence and snapshot contract

`reference_runner.cpp` provides a closed opcode legality/dispatch gate and the minimal global state required by the selected reference handlers. Each instruction calls the original `dppc_interpreter` implementation in the checked-out `dingusppc/cpu/ppc/ppcopcodes.cpp`. Original handler operand extraction, arithmetic, masks, flags, branch conditions and target calculations execute unchanged. Function sections plus linker garbage collection remove unused handlers and their machine-service dependencies. In v1 no memory, timer or exception semantic stubs are linked. The explicitly enabled v2 service backend is described below.

LR/CTR access uses `fixed_spr<8|9, read|write>` wrappers. Each wrapper preserves the encoded GPR selector and fixes the already-authorized primary opcode, SPR and XO fields before calling original `ppc_mfspr`/`ppc_mtspr` (`ppcopcodes.cpp:983–1161`). GCC's `flatten` attribute and `-flto` inline and specialize those original handlers, eliminating unreachable timer/MMU/other-SPR branches. The wrapper contains no register-read/write semantics. If the compiler cannot remove the inaccessible service references, the executable fails to link; it does not fall back to stubbed operations. This intentionally requires the documented GCC build configuration. Original source files remain unmodified.

This adapter **does not execute the original full opcode dispatcher**, call `ppc_cpu_init`, or initialize a Macintosh machine. PVR is set to `0x00070101` for MPC603EV/PID7v or `0x00060101` for MPC603E/PID6; `is_601` is false, no `include_601` path is enabled, and both endian feature macros are zero. Those model labels identify configuration, not distinct PID timing validation. Default MPC603EV is the measured acceptance lane; the optional PID6 selection uses the same selected handlers and is not separately certified here.

Version 1 snapshots contain exactly 38 eight-digit hexadecimal fields:

```text
pc insn gpr0 gpr1 ... gpr31 cr xer lr ctr
```

`pc`/`insn` identify the executed instruction; registers and flags are the state **after** that instruction. The next row's PC checks branch flow. There is no explicit final next-PC, cycle count, speculative state, FPR/FPSCR, exception state or memory field. The generated manifest records `schema_version: 1` and the complete ordered `snapshot_fields`; bare trace files follow this fixed format rather than embedding a header.

The actual-core bench emits pre-edge retiring PC/word, then samples the real GPR file and CR/XER/LR/CTR after the commit edge's nonblocking updates. It has no instruction oracle or expected architectural values. It uses the current package type without depending on its packed width. Architectural initialization is reset-zero state followed by real `addi`, `addis` and `ori` instructions. Model PVR initialization affects only reference metadata; no compared register is injected. Fetch latency, request backpressure and retirement stalls vary deterministically, and the bench asserts held request/retirement stability and no unexpected memory request, diagnostic halt or external redirect acceptance.

`compare_state.py` compares the shared row prefix first, reporting the first divergent row, PC, field and values. It then rejects a missing or extra retirement with its index and PC. It rejects empty traces, unknown digits, wrong widths and wrong field counts. There is no masked comparison or tolerated mismatch list.

## Measured supported corpus

On 2026-09-14, the expanded default configuration passed **8,500 snapshots × 38 fields**, with **142 encoding groups**, 258 stalled fetch-request observations and 4,149 stalled retirement observations. The 8,502-word image contains call/return sequences and two taken BCCTR branches that skip legal instructions. Encoding groups include initialization/call labels and must not be read as distinct architectural instruction counts. The current canonical core's `DIV_LATENCY=20` default was used; the bench waits for retirement and imposes no one-cycle divide assumption. This demonstrates tolerance of the implementation's longer divider, not conformance to manual divide timing.

| Handler family | Generated acceptance coverage |
|---|---|
| ADD, ADDC, ADDE, ADDME, ADDZE, SUBF, SUBFC, SUBFE, SUBFME, SUBFZE, NEG | All OE/Rc combinations; both committed incoming CA states; seven operand pairs including zero, signed bounds, minus one and carry/overflow corners; destination/source aliasing |
| SUBFIC, ADDIC, ADDIC., ADDI, ADDIS | Four immediate patterns, real nonzero r0 source where architectural rules require it |
| ORI/ORIS, XORI/XORIS, ANDI./ANDIS. | Four immediate patterns and full state preservation |
| AND, ANDC, EQV, NAND, NOR, OR, ORC, XOR | Both Rc forms, nontrivial bit patterns, source/destination alias |
| SLW, SRW, SRAW, SRAWI | Both Rc forms; zero/one/15/31/32/63/64/255 counts (SRAWI encodes low five immediate bits); negative/discarded-bit cases |
| RLWIMI, RLWINM, RLWNM | Both Rc forms; full, wrapped and single-bit masks; old merge destination; register count with high bits set |
| CMP/CMPL, CMPI/CMPLI | All eight BF destinations, L=0 |
| Eight CR logical operations | All 32 destination bits, overlapping old-source/destination bits |
| MULLW | All OE/Rc forms, six operand pairs including signed overflow and both signed bounds; SO/OV/CA seeded by actual ADDCO. before each case |
| MULLI, MULHW, MULHWU | Five values × five signed immediates for MULLI; both Rc forms and six signed/unsigned product pairs for high multiply; source/destination aliases including ordinary r0 |
| DIVW, DIVWU | All OE/Rc forms, nine defined pairs each; zero numerator, quotient zero, both signs, truncation toward zero, signed bound divided by a non-overflowing divisor; seeded SO/OV/CA and immediate dependent ADDI consumer |
| CNTLZW, EXTSB, EXTSH | Both Rc forms, ten patterns including zero, sign boundaries and all ones; r0 source/destination alias |
| MFCR, MTCRF | All 256 field masks, changing full CR patterns and immediate MFCR readback into ordinary r0 |
| MCRF, MCRXR | All 64 MCRF field pairs; MCRXR to every BF with reachable XER states `E`, `A`, zero, then actual ADDE. consumes the cleared CA/SO |
| MFSPR/MTSPR LR/CTR | Both directions, five 32-bit patterns each including unaligned LR/CTR values; real GPR0 read/write and dependent consumer |
| B, BC | All AA/LK combinations; BC exercises the reviewed legal BO set, with next-instruction targets |
| BCLR | Both LK forms in actual taken call/return sequences; old LR target behavior and new LR state |
| BCCTR | Both LK forms, not-taken and actual taken nonsequential targets; real MTCTR setup includes nonzero low two bits, then MFCTR/MFLR readback |

The arithmetic sequence causes real CA changes, OV set/clear and sticky SO propagation, then subsequent record operations observe SO. Other CR fields become nonzero through actual comparison/CR instructions and remain part of every full-state comparison. This is selected operand coverage, not exhaustive inputs, opcode-bit legality, all branch truth combinations, or all implemented RTL forms.

The closed gate rejects reserved BO encodings, BCCTR forms that decrement CTR, nonzero reserved unary rB, compare L/reserved bits, reserved CR fields/Rc, high-multiply OE, unsupported SPR numbers and unsupported primary/XO values. Current CPU decode admits SPR8/9 only: **XER SPR moves remain rejected**, although the generic original reference handler has an XER branch. This avoids silently adding CPU scope or treating arbitrary XER reserved bits as validated. XER[28:0] starts zero and cannot be seeded in either lane; MCRXR's original fourth-bit handling consequently agrees on these reachable states, without resolving the reserved-bit question in [`CR_STATE.md`](CR_STATE.md).

The run separately reconciles executed encodings against the source-owned ISA metadata. All **140 non-memory forms** of `isa.json`'s 168 implemented entries are hit; the exact `covered` and `uncovered` ID lists and metadata hash are stored in the manifest. Metadata supplies inventory labels only, never expected state. Any uncovered implemented non-memory entry fails the acceptance run. The 28 currently uncovered entries are exactly: `lwz, lbz, stw, stb, lhz, lha, sth, lwzx, lbzx, stwx, stbx, lhzx, lhax, sthx, lwzu, lbzu, lhzu, lhau, stwu, stbu, sthu, lwzux, lbzux, lhzux, lhaux, stwux, stbux, sthux`. Other architecture instructions absent from the current decode inventory, privileged/system operations, FP and atomics also remain unsupported. The source gate is the exact membership definition; unit tests independently enumerate accepted family/modifier groups and anchor complete MTCRF masks, MCRF pairs and taken-BCCTR structure. Inventory coverage does not imply exhaustive operands or legality-bit testing.

## Negative evidence and artifacts

The same public comparator executable is run against the actual RTL trace with eight independent expected-field corruptions: PC, instruction, GPR0, GPR3, CR, XER, LR and CTR. Every mutation must fail with its exact field name. Four further CLI cases truncate or extend the actual trace, supply malformed fields, or supply an empty trace. All **12 negative comparisons** failed as required.

The real reference binary also rejected **43 gates**: 30 static encoding/model cases and 12 dynamic exceptional-divide cases plus the direct reset-state divide-zero case. These include high-multiply reserved OE, reserved unary/CR bits and Rc, SPR1/other SPR numbers, reserved SPR Rc, compare L=1, reserved BO, BCCTR counter-decrement forms, memory, unknown opcode and MPC602. Dynamic divide guards cover signed/unsigned zero divisor and signed overflow in every OE/Rc form after two real setup instructions, and verify that no exceptional divide snapshot was emitted. The local Python suite passes **13 tests** (seven unchanged parser tests and six comparison/corpus tests), including first-divergence precedence over length mismatch. These checks establish comparator sensitivity and bounded input rejection; they do not prove the independent reference itself is correct.

The isolated build directory holds `program.hex`, `expected.txt`, `actual.txt`, compiler/RTL/compare logs, binaries, copied `DINGUSPPC-LICENSE` and `DINGUSPPC-CREDITS.md`, and `manifest.json`. The manifest records source commit/dirty state, selected source/header/adapter/RTL/ISA SHA-256 hashes, compiler versions and complete build commands, binary/program/trace hashes, configuration, encoding counts, exact form coverage, rejection cases and negative diagnostics. It is a run artifact, not a checked-in golden trace. At the measured run the original checkout commit is `cf951f690013cc9466c398d0428d4df50b6ede45` and its working tree is clean.

## P13d: explicit v2 flat-memory execution

Run from the repository root:

```sh
python3 sim/cosim/run_memory_reference.py \
  --build-dir build/ppc603e-memory-reference-build
python3 sim/cosim/compare_memory.py \
  build/ppc603e-memory-reference-build/expected.txt \
  build/ppc603e-memory-reference-build/actual.txt
```

This builds the same unmodified original handler source with the additional explicit flag `-DREFERENCE_FLAT_RAM=1`. The selected original load/store implementations are `ppc_st/stu/stx/stux`, `ppc_lz/lzu/lzx/lzux` and `ppc_lha/lhau/lhax/lhaux` in `dingusppc/cpu/ppc/ppcopcodes.cpp:1630–1884`. The original handlers perform effective-address arithmetic, old source capture, signed/unsigned extension, destination writes and update-register writes. The adapter does not reimplement those instruction semantics.

The adapter supplies only the `mmu_read_vmem<T>` and `mmu_write_vmem<T>` service signatures declared in `ppcmmu.h:104–107`, for byte, halfword and word values. These services access a zero-initialized **256-byte big-endian RAM at `0x1000..0x10ff`**. They check the entire access range and size alignment before reading or writing any bytes; stores cannot partially mutate RAM before a bounds failure. This is a flat service replacement: the original `ppcmmu.cpp` is not built and no translation, permissions, BAT/PAT/TLB, cache, MMIO, device, parity or 60x transaction behavior is claimed.

The **immutable instruction image is a separate Harvard address space**. Its numerical addresses overlap the data RAM interval in this corpus, but data stores never alter instruction fetch. There is no self-modifying-code, instruction/data coherency or unified-memory claim.

The v2 gate enables exactly the 28 base/update D/indexed scalar forms listed in the v1 uncovered inventory above. It rejects Rc=1 for indexed forms, rA=0 for every update form, and rA=rD for update loads. Store-update rS=rA and indexed source aliases are valid and remain enabled. The original handlers' invalid-update branches retain a call to `ppc_exception_handler`; the v2 adapter implements that escape solely by throwing an unsupported-reference error, never by fabricating architectural exception state or treating a failed operation as successful. The gate normally prevents those branches. Backend range/alignment failures likewise exit 2, with no snapshot for the failed instruction. Setup instructions already executed can leave a valid trace prefix, so callers must check the executable's exit status.

### V2 schema and actual-core backend

Every v2 trace begins with this exact mandatory header:

```text
#ppc-reference-v2 ram_base=00001000 ram_bytes=00000100
```

Each following row has **102 hex32 fields**: the unchanged 38 v1 register fields, followed by all 64 RAM words in increasing addresses `0x1000, 0x1004, ..., 0x10fc`. Each word is assembled in big-endian byte order. The comparator names a mismatching word, for example `ram[00001004]`; no digest, memory masking or tolerated differences are used. `compare_memory.py` requires the v2 header and size. The v1 parser/CLI still requires exactly 38 fields and rejects v2 input; the v2 parser rejects bare v1 input. The common comparison function has an explicit optional field-name argument whose default remains v1.

`tb_core_memory_reference.sv` executes the real core with a separate byte-array data backend. It accepts aligned word-address requests, applies the core's byte strobes to RAM on store-request acceptance, and returns a registered response after varying latency. Request backpressure varies independently. Read responses contain the full aligned word; original CPU lane selection and sign extension must produce the correct committed result. Store RAM effects can precede retirement after the core's irrevocable reservation, as specified in [`CONTROL_MEMORY.md`](CONTROL_MEMORY.md). The current core serializes memory operations after older retirement and blocks younger work, so comparing RAM at each retirement observes the same instruction ordering as the reference. This is not a general speculative-store or rollback model.

The bench checks held instruction/data requests and responses, stable stalled retirement packets, and that GPR/CR/XER/LR/CTR never change on an edge without accepted retirement. Each retirement exports every architectural register and every RAM word after nonblocking updates, checking both update destinations together through the independent reference trace. It also requires exact memory-request/store counts derived from the executed reference instruction stream; a duplicate read cannot pass merely because the final architectural value repeats.

### V2 measured coverage and negative tests

The measured normal program has **9,883 words, 9,881 executed retirements, 170 encoding groups and all 168 implemented ISA decode entries**. No implemented metadata form remains uncovered. It includes all original v1 arithmetic/flag/branch/CR/SPR operations and **240 memory operations: 106 loads and 134 stores**. The bench observed 175 stalled data-request cycles, 293 stalled instruction-request cycles and 4,759 stalled retirement cycles.

Memory coverage includes all four byte lanes and both halfword positions over both word halves; full-word transfers; signed positive/negative LHA values through all four forms; negative D displacements; indexed addressing; update load/store base effects; immediate dependent use of loaded and updated values; rA=rD base loads; rD=rB update loads; old rA=rB address inputs; old rS=rA and rS=rA=rB store-update inputs; rA=0 with ordinary nonzero r0 index/source; and accesses at both RAM boundaries. Every RAM word is initialized through actual STW instructions, and later masked stores must preserve neighboring bytes. No source-versus-RTL alias divergence was found in this corpus.

The real v2 CLI passes **13 injected-failure checks**: separate updated-base and loaded-result corruption, CR/XER corruption, corruption in each byte lane of the first RAM word, corruption at the far RAM boundary, v1 input, empty v2 input, truncation and a short row. The real reference executable passes **69 rejection cases** covering every update form's rA=0 restriction, every update load's rA=rD restriction, every indexed form's Rc bit, lower/upper out-of-range accesses and misalignment before any failed-operation snapshot. These are bounded input/backend rejection tests, not architectural exception tests.

The unchanged v1 execution was rerun separately after integration: **8,500 snapshots, 140 forms, 12 mismatch checks and 43 rejection gates pass**. The combined local Python suite passes **17 tests**, retaining the original seven parser tests and adding strict v1/v2 separation, header/shape failures, every RAM word/byte-lane comparator sensitivity, and independent memory-encoding anchors. The v2 manifest records source/build hashes, full field order, RAM parameters, both address-space roles, exact form/count coverage and negative outcomes.

## Provenance and remaining P13 scope

See [REFERENCE_AUDIT.md](REFERENCE_AUDIT.md) for the prior source audit and parser details. The original handler file carries the DingusPPC Development Team copyright and GPL version 3-or-later notice (`ppcopcodes.cpp:1–20`); the project also provides `LICENSE` and `CREDITS.md`. The adapter is explicitly GPL-3.0-or-later. No original source is copied into canonical RTL or modified; the reference remains separately built and separately executed. Redistribution of the linked reference executable must carry the corresponding source and applicable notices/license obligations; the copied license and recorded hashes alone are not a source-distribution package.

Remaining work includes larger/randomized instruction streams, original full-decoder cross-checks, eventual XER/other SPR support, integrated faults/recovery, FP/FPSCR and exception snapshots, and model/LE/MMU validation. The v2 memory lane covers normal aligned flat-RAM operations only. Undefined-result divide behavior remains a deliberate oracle gap even though the RTL has a deterministic implementation policy. DingusPPC remains a functional reference with its own possible bugs. A mismatch must be triaged against the primary architecture source rather than automatically changing RTL to match the emulator. These lanes give no evidence for 603e stage timing, resource occupancy, cache/MMU geometry, bus-cycle fidelity or electrical behavior.
