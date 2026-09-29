#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
set -euo pipefail

if [[ $# -ne 2 || ( "$1" != 0 && "$1" != 1 ) ]]; then
    echo 'usage: build_candidate.sh TECH{0|1} OUTPUT_DIR' >&2
    exit 2
fi
tech=$1
out=$(realpath -m "$2")
repo=$(cd "$(dirname "$0")/../.." && pwd)
ghdl_bin=${GHDL_BIN:-ghdl}
mkdir -p "$out"
if [[ $("$ghdl_bin" --version | head -n 1) != 'GHDL 4.1.0 (Ubuntu 4.1.0+dfsg-0ubuntu2.1) [Dunoon edition]' ]]; then
    echo 'GHDL 4.1.0 Ubuntu package is required' >&2
    exit 1
fi
if [[ -n ${YOSYS_BIN:-} ]]; then
    yo_bin=$YOSYS_BIN
elif command -v yosys >/dev/null; then
    yo_bin=$(command -v yosys)
else
    pkg="$out/tools/yosys_0.33-5build2_amd64.deb"
    mkdir -p "$out/tools"
    if [[ ! -e $pkg ]]; then
        curl -fsSL 'https://archive.ubuntu.com/ubuntu/pool/universe/y/yosys/yosys_0.33-5build2_amd64.deb' -o "$pkg"
    fi
    echo '94247f2157ec6ce63c6638326e419975d911ace5356b3dc276d1d8b36659efbd  '"$pkg" | sha256sum -c -
    dpkg-deb -x "$pkg" "$out/tools"
    yo_bin="$out/tools/usr/bin/yosys"
fi
if [[ $("$yo_bin" -V) != 'Yosys 0.33 (git sha1 2584903a060)' ]]; then
    echo 'Yosys 0.33 Ubuntu package is required' >&2
    exit 1
fi

"$ghdl_bin" -a --std=08 --workdir="$out" \
    "$repo/rtl/fpu/ss/base_pack.vhd" \
    "$repo/rtl/fpu/ss/fpu_pack.vhd" \
    "$repo/rtl/fpu/ss/fpu_mul.vhd" \
    "$repo/rtl/fpu/ss/fpu_div.vhd" \
    "$repo/rtl/fpu/ss/fpu_calc.vhd"
"$ghdl_bin" --synth --std=08 --workdir="$out" --out=verilog \
    -gDENORM_HARD=true -gDENORM_FTZ=false -gDENORM_ITER=false \
    -gTECH="$tech" fpu_calc > "$out/fpu_calc_raw.v"
"$yo_bin" -Q -p \
    "read_verilog $out/fpu_calc_raw.v; hierarchy -top fpu_calc; proc; opt; pmuxtree; opt; clean -purge; write_verilog -noattr $out/fpu_calc.v" \
    > "$out/yosys.log"
python3 "$repo/rtl/fpu/canonicalize_candidate.py" "$tech" "$out/fpu_calc.v"
echo "Generated $out/fpu_calc.v (TECH=$tech)"
