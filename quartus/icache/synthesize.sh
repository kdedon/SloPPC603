#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Standalone cache storage inference gate; no integrated fit or timing claim.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
mode="${1:-local}"
. "${script_dir}/../../ci/pins.env"
image="${QUARTUS_IMAGE:-${QUARTUS_IMAGE_PIN}}"
case "${mode}" in local|--docker) ;; *) echo "usage: $0 [--docker]" >&2; exit 2 ;; esac
python3 "${script_dir}/../qsf_sources.py" "${script_dir}"
evidence_dir="${script_dir}/evidence/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "${evidence_dir}" "${script_dir}/output_files"
trap 'printf "%s\n" "$?" > "${evidence_dir}/script-exit-status.txt"' EXIT
manifest() {
  (cd "${script_dir}" && sha256sum ../../rtl/ppc_ram_sdp.sv ../../rtl/ppc_ram_lut.sv ../../rtl/ppc_icache.sv files.f ppc_icache_storage.qsf ppc_icache_storage.qpf synthesize.sh ../qsf_sources.py)
}
manifest > "${evidence_dir}/source-before.sha256"
if [[ "${mode}" == local ]]; then
  quartus_sh --version > "${evidence_dir}/tool-versions.txt"
  compile=(quartus_map --read_settings_files=on --write_settings_files=off ppc_icache_storage -c ppc_icache_storage)
else
  docker image inspect --format 'id={{.Id}} repo_digests={{json .RepoDigests}}' "${image}" > "${evidence_dir}/image.txt"
  docker run --rm --network none "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_sh --version > "${evidence_dir}/tool-versions.txt"
  compile=(docker run --rm --network none --user "$(id -u):$(id -g)" --volume "${repo_dir}:/work" --workdir /work/quartus/icache "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_map --read_settings_files=on --write_settings_files=off ppc_icache_storage -c ppc_icache_storage)
fi
rm -f "${script_dir}/output_files/ppc_icache_storage.map.rpt"
set +e
(cd "${script_dir}" && "${compile[@]}") 2>&1 | tee "${evidence_dir}/build.log"
compile_status=${PIPESTATUS[0]}
set -e
printf '%s\n' "${compile_status}" > "${evidence_dir}/compile-exit-status.txt"
manifest > "${evidence_dir}/source-after.sha256"
report="${script_dir}/output_files/ppc_icache_storage.map.rpt"
if [[ -f "${report}" ]]; then cp "${report}" "${evidence_dir}/"; fi
echo "Evidence: ${evidence_dir}"
if ! cmp -s "${evidence_dir}/source-before.sha256" "${evidence_dir}/source-after.sha256"; then
  echo "ERROR: cache synthesis sources changed during compilation" >&2
  exit 3
fi
if (( compile_status != 0 )); then exit "${compile_status}"; fi
if ! grep -Eq 'Implemented 0 input pins' "${evidence_dir}/build.log" ||
   ! grep -Eq 'Implemented 0 output pins' "${evidence_dir}/build.log" ||
   ! grep -Eq 'Design contains 374 virtual pins' "${evidence_dir}/build.log"; then
  echo "ERROR: expected all 374 cache ports to be virtual and zero physical I/O" >&2
  exit 4
fi
if grep -Eq 'RAM logic .*uninferred' "${evidence_dir}/build.log"; then
  echo "ERROR: cache RAM inference was not confirmed" >&2
  exit 4
fi
python3 - "${evidence_dir}/ppc_icache_storage.map.rpt" <<'PY'
import sys
from pathlib import Path
rows = [[field.strip() for field in line.split(';')]
        for line in Path(sys.argv[1]).read_text().splitlines()]
def ram(name, kind, depth, width):
    size = str(int(depth) * int(width))
    assert any(len(row) > 9 and row[1].startswith(name) and row[2] == kind
               and row[3:9] == ['Simple Dual Port', depth, width, depth, width, size]
               for row in rows), f'missing {depth} x {width} {kind} {name} in synthesis RAM Summary'
for way in range(4):
    ram(f'ppc_ram_sdp:g_way[{way}].data_ram|', 'M10K block', '256', '128')
    ram(f'ppc_ram_lut:g_way[{way}].tag_ram|', 'MLAB', '128', '20')
ram('ppc_ram_lut:lru_ram|', 'MLAB', '128', '8')
ram('ppc_ram_lut:way_valid_ram|', 'MLAB', '128', '4')
print('PASS: four 256 x 128 M10K data RAMs, four 128 x 20 MLAB tag RAMs, 128 x 8 LRU and 128 x 4 way-valid MLAB RAMs')
PY
