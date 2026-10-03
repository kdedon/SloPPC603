#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
#
# Fetch pinned Berkeley SoftFloat 3 and TestFloat 3, verify them, add a
# PowerPC specialization and build testfloat_gen. Usage:
#   fetch-softfloat.sh [output-dir]      (default sim/build/testfloat)
# The sources are third-party (BSD-3-Clause); they stay in the ignored
# build directory and are never committed.
set -eu

SOFTFLOAT_COMMIT=a0c6494cdc11865811dec815d5c0049fba9d82a8
SOFTFLOAT_SHA256=1f719bcc8878be9627f6cfc44a0d6dbddf32bacc70ac81193bcbf2c62f97cbe9
TESTFLOAT_COMMIT=a9c849f1b0eb0264b626d9686ffae167d996e3be
TESTFLOAT_SHA256=54852fd1d11f0109011e54d69952cda097d3c49709ce46e4800353a6e8c764c3

OUT=${1:-$(dirname "$0")/../build/testfloat}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
GEN="$OUT/testfloat_gen"

fetch() {  # repo commit sha256 name
    archive="$OUT/$4.tar.gz"
    [ -f "$archive" ] || curl -sSfL -o "$archive" \
        "https://codeload.github.com/ucb-bar/$1/tar.gz/$2"
    echo "$3  $archive" | sha256sum -c --quiet -
    rm -rf "${OUT:?}/$4"
    mkdir "$OUT/$4"
    tar -xzf "$archive" -C "$OUT/$4" --strip-components=1
}
fetch berkeley-softfloat-3 $SOFTFLOAT_COMMIT $SOFTFLOAT_SHA256 softfloat
fetch berkeley-testfloat-3 $TESTFLOAT_COMMIT $TESTFLOAT_SHA256 testfloat

# PowerPC specialization from 8086-SSE, which already returns the first NaN
# operand quieted (frA before frB): positive default QNaN, tininess before
# rounding, and fctiw saturation (0x7FFFFFFF positive, 0x80000000 negative
# or NaN).
SRC="$OUT/softfloat/source"
cp -r "$SRC/8086-SSE" "$SRC/PowerPC"
sed -i \
    -e 's/^#define init_detectTininess .*/#define init_detectTininess softfloat_tininess_beforeRounding/' \
    -e 's/^#define i32_fromPosOverflow .*/#define i32_fromPosOverflow  0x7FFFFFFF/' \
    -e 's/^#define defaultNaNF16UI 0xFE00/#define defaultNaNF16UI 0x7E00/' \
    -e 's/^#define defaultNaNF32UI 0xFFC00000/#define defaultNaNF32UI 0x7FC00000/' \
    -e 's/^#define defaultNaNF64UI UINT64_C( 0xFFF8000000000000 )/#define defaultNaNF64UI UINT64_C( 0x7FF8000000000000 )/' \
    "$SRC/PowerPC/specialize.h"
for pattern in 'tininess_beforeRounding' 'i32_fromPosOverflow  0x7FFFFFFF' \
               'F32UI 0x7FC00000' 'F64UI UINT64_C( 0x7FF8'; do
    grep -q "$pattern" "$SRC/PowerPC/specialize.h"
done

make -s -C "$OUT/softfloat/build/Linux-x86_64-GCC" SPECIALIZE_TYPE=PowerPC \
    softfloat.a >/dev/null
make -s -C "$OUT/testfloat/build/Linux-x86_64-GCC" \
    SOFTFLOAT_DIR="$OUT/softfloat" SPECIALIZE_TYPE=PowerPC testfloat_gen >/dev/null
cp "$OUT/testfloat/build/Linux-x86_64-GCC/testfloat_gen" "$GEN"
echo "$GEN"
