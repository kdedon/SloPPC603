#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Fetches the benchmark sources at pinned upstream commits into
# toolchain/build/demo/src and checks each file's SHA-256. Nothing fetched
# here is committed. Files already present with the right hash are kept.
#   Dhrystone 2.1: https://github.com/Keith-S-Thompson/dhrystone/tree/66bb9df1a5dea67f33437b856bf68ae52bd5c90f/v2.1
#   CoreMark:      https://github.com/eembc/coremark/tree/1f483d5b8316753a742cbf5590caf5bd0a4e4777
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/build/demo/src"
host=https://raw.githubusercontent.com

fetch() {  # dir url-base file sha256
  out="$dest/$1/$3"
  mkdir -p "$dest/$1"
  if [ -f "$out" ] && echo "$4  $out" | sha256sum -c --status; then
    return
  fi
  curl -sfL --retry 3 -o "$out.tmp" "$2/$3"
  if ! echo "$4  $out.tmp" | sha256sum -c --status; then
    rm -f "$out.tmp"
    echo "fetch-benchmarks: $1/$3 does not match its pinned SHA-256" >&2
    exit 1
  fi
  mv "$out.tmp" "$out"
}

dhry="$host/Keith-S-Thompson/dhrystone/66bb9df1a5dea67f33437b856bf68ae52bd5c90f/v2.1"
fetch dhrystone "$dhry" dhry.h 73be10649f198698cf40a48659d079123e45ef2542d275e6885427e4eb10d503
fetch dhrystone "$dhry" dhry_1.c 958069f6ff8fe099ac6121d5f590fa8207bc32a744f138be721bc7358d143cbb
fetch dhrystone "$dhry" dhry_2.c 7954383013caead70e8283375b249ecbaa1aaf092b526acbcac3f187a015c108

cm="$host/eembc/coremark/1f483d5b8316753a742cbf5590caf5bd0a4e4777"
fetch coremark "$cm" coremark.h 42642b9a06c7ed2b3bd9eda971b7c3868c4f5d27bf7ef6c4bba11291a0c2598a
fetch coremark "$cm" core_list_join.c ca00e4e010ece47d7f040cb92aa50a95345a00d3171b59d088f6b243be06ce7b
fetch coremark "$cm" core_main.c 17884c93c5b94378eb0ff02b4df3725756cf2addb9b8cbcaa6200a4649ff5ca7
fetch coremark "$cm" core_matrix.c ecdff717b5a5c4907d221a606760e25499899cbf617582c05d40db71c91351e4
fetch coremark "$cm" core_state.c f4b84bb0a3452c45a4daa664ab502bfdccbd31cb57d93e9ac490c60937717a4e
fetch coremark "$cm" core_util.c a3fbfcb9bb943b638624b8ece01c5836dd56a96d7bcde2697b248d077447327f
echo "fetch-benchmarks: sources verified in $dest"
