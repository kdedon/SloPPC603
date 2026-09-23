#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "${temp_dir}"' EXIT

for pass in one two; do
  make -C "${script_dir}" --no-print-directory \
    BUILD_DIR="${temp_dir}/${pass}" all check
  find "${temp_dir}/${pass}" -type f \
    \( -name 'smoke.elf' -o -name 'smoke.bin' -o -name 'smoke.dump' \) \
    -printf '%P\0' | sort -z | while IFS= read -r -d '' artifact; do
      sha256sum "${temp_dir}/${pass}/${artifact}" | sed "s#${temp_dir}/${pass}/##"
    done > "${temp_dir}/${pass}.sha256"
done

diff -u "${temp_dir}/one.sha256" "${temp_dir}/two.sha256"
mkdir -p "${script_dir}/build"
cp "${temp_dir}/one.sha256" "${script_dir}/build/artifacts.sha256"
echo "PASS: two clean builds produced identical ELF, binary, and disassembly files"
