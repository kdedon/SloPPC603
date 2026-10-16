<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Cached64 Dhrystone: fetch hints off/on

Recorded: standard `tb_demo_soc`, source `92b4e7464aab4f7cb3c12a92ad2a739e8eb2042e` plus documentation-only clarifications, 2026-10-16. No DUT or observer changes.

Fetch hints off and on both passed the original **23 firmware checks, zero mismatches**, with identical performance counters and complete stdout after replacing only each run's owned output-directory path. All 69 profile rows matched. This is a matched cached64 execution result, not a full retirement-tuple equivalence proof.

## Profile, inputs and results

Both runs use FPU1/FULL, data cache1 and therefore64-bit data memory, DW2/FW2, LSU1, FDREG0, immediate mispredict fetch1 and branch removal0. They use the same compiled Dhrystone2.1 image for2,000 runs, original clocks/bench, unique initialization, seed1/reset2 and local256KiB RAM. All 32,768 64-bit RAM words are zeroed before image loading; CPU state retains randomized initialization. Image SHA256 is `9e8788c32815aec52ebbad8ea913ecc3afebf8f242ae3ab2663cf04db4eef2a6`; dump SHA256 is `3fc726a3853abb0ace9794ed3dfaac2087cc90b54a90c801bd298dac5124a6cb`. DUT/input fingerprints matched between the runs.

| Metric | Hints off | Hints on |
|---|---:|---:|
|Firmware performance-window cycles|1,154,918|1,154,918|
|Firmware performance-window retirements|1,180,116|1,180,116|
|Printed cycles/run|577.3|577.3|
|Whole-model cycles|2,195,096|2,195,096|
|Whole-model retirements|1,624,033|1,624,033|
|Whole-model CPI|1.352|1.352|
|Bus tenures / frames|30,884 /11|30,884 /11|

The identical 69-row profile includes nonzero fast-store activity: other-other accepted14,002, store-same accepted6,002 and store-other accepted4,004. These existing internal profile counters demonstrate activity in this workload; they are not a complete independent cache-use certificate or architectural oracle.

The first post-run validator incorrectly expected one space in the padded `checks:          23` line. It was repaired to accept whitespace while still requiring exactly23 checks and zero mismatches. The original simulations had passed; no model rerun or numerical/oracle relaxation was needed.

## Reproduction

From the recorded source, first provide the pinned image and dump using the existing firmware build instructions in `toolchain/README.md`. The following expands the canonical `demo-soc-fpu-model` recipe with one compiler worker instead of its original two; no new benchmark engine is used. Run from the repository root in Bash:

```sh
cd sim
for hints in 0 1; do
  output=build/cached64-profile
  hint_parameter=()
  if [ "$hints" = 1 ]; then
    output=build/cached64-profile-hints1
    hint_parameter=("-GENABLE_FETCH_HINTS=1'b1")
  fi
  mkdir -p "$output/demo"
  cp ../toolchain/build/demo/dhrystone.hex "$output/frozen.hex"
  PPC_VERILATOR_FLAGS='+define+PPC_DISPATCH_WIDTH=2 +define+PPC_BRANCH_REMOVAL=0 +define+PPC_FETCH_DECODE_REG=0 +define+PPC_MISPREDICT_FETCH_NOW=1' \
  OBJCACHE= tools/verilate-lsu-pipe --binary --timing --assert -Wall -O3 -j 1 \
    --x-assign unique --x-initial unique --top-module tb_demo_soc \
    "-GENABLE_FPU=1'b1" "${hint_parameter[@]}" \
    --Mdir "$output/demo/model-fpu" \
    $(cat ../rtl/chip_files.f ../rtl/fpu_files.f ../rtl/soc/files.f) \
    -I../tb ../tb/soc/tb_demo_soc.sv
  "$output/demo/model-fpu/Vtb_demo_soc" \
    +verilator+seed+1 +verilator+rand+reset+2 \
    "+IMAGE=$(pwd)/$output/frozen.hex" +NAME=dhrystone +PROFILE \
    +INTEGER_PAIR_ZERO_RAM "+PPM=$(pwd)/$output/demo/dhrystone.ppm" \
    > "$output/run.log"
done
python3 - <<'PY'
from pathlib import Path
import re
logs=[]
for directory in ('cached64-profile','cached64-profile-hints1'):
    owned=(Path('build')/directory).resolve()
    text=(owned/'run.log').read_text()
    assert re.search(r'^checks:\s+23, mismatches 0$', text, re.M)
    assert sum(line.startswith('profile ') for line in text.splitlines()) == 69
    assert 'INTEGER_PAIR_RAM_INIT words=32768 bits=64 fill=0 before_image=1' in text
    logs.append(text.replace(str(owned), '<owned-output>'))
assert logs[0] == logs[1], 'stdout differs beyond owned output-directory paths'
print('PASS original checks and complete matched stdout')
PY
```

Check the image/dump hashes above before running. Keep the same source, image, initialization, compiler flags and clocks across both arms. The hints-off arm uses the recorded default-off parameter; the hints-on arm adds only its explicit parameter.

## Limits

The older27-field retirement-stream observer and its source guard were not enabled or changed. This run adds no new observer and establishes no complete public memory/exception or cached-use certificate. Identical existing outputs and checks are bounded evidence for this image and profile, not all-state or all-program equivalence.

The earlier uncached32 benchmark changes both cache configuration and data width relative to this cached64 profile. Its public loop window and this firmware window also differ; do not divide the old6.48million public-loop cycles by this1.15million firmware-window count. A matched firmware-window comparison would use the old6,483,181 figure, but still would not isolate a cache effect or constitute a code optimization. No such speedup ratio is asserted here.

Local RAM timing is not MiSTer DDR timing. FPU-off CPU fitting results, including43.15MHz, do not establish timing closure for this FPU-on cached64 model. No66MHz or aggregate CI claim follows from this benchmark.
