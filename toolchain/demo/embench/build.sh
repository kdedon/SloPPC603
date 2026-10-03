#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Builds the fetched Embench-IoT benchmarks into one relocatable object.
# Each benchmark's files link into one object whose entry points are renamed
# emb_<id>_{init,warm,benchmark,verify}; every other global symbol it defines
# becomes local, so the benchmarks can share an image.
#   build.sh <out-dir> <embench-dir> <repeat-divisor> <benchmark>... -- <cc and flags>...
set -eu
out=$1 src=$2 div=$3
shift 3
names=
while [ "$1" != "--" ]; do names="$names $1"; shift; done
shift
objcopy=${OBJCOPY:-powerpc-linux-gnu-objcopy}
rm -rf "$out"
mkdir -p "$out"
# benchmark() runs LOCAL_SCALE_FACTOR * CPU_MHZ repeats; this makes it
# LOCAL_SCALE_FACTOR / div, at least one.
mhz="-DCPU_MHZ=1/$div+(LOCAL_SCALE_FACTOR<$div)"
"$@" -I"$src/support" -c "$src/support/beebsc.c" -o "$out/beebsc.o"
parts="$out/beebsc.o"
for name in $names; do
  id=$(echo "$name" | tr - _)
  objs=
  for c in "$src/src/$name"/*.c; do
    o="$out/$name-$(basename "$c" .c).o"
    "$@" -I"$src/support" "$mhz" -c "$c" -o "$o"
    objs="$objs $o"
  done
  # shellcheck disable=SC2086
  "$@" -r -nostdlib -o "$out/$name.r.o" $objs
  "$objcopy" --redefine-sym initialise_benchmark="emb_${id}_init" \
    --redefine-sym warm_caches="emb_${id}_warm" \
    --redefine-sym benchmark="emb_${id}_benchmark" \
    --redefine-sym verify_benchmark="emb_${id}_verify" \
    -G "emb_${id}_init" -G "emb_${id}_warm" -G "emb_${id}_benchmark" -G "emb_${id}_verify" \
    "$out/$name.r.o" "$out/$name.o"
  parts="$parts $out/$name.o"
done
# shellcheck disable=SC2086
"$@" -r -nostdlib -o "$out/benchmarks.o" $parts
