#!/usr/bin/env bash
# Standalone cache storage inference gate; no integrated fit or timing claim.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
mode="${1:-local}"
image="${QUARTUS_IMAGE:-theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70}"
case "${mode}" in local|--docker) ;; *) echo "usage: $0 [--docker]" >&2; exit 2 ;; esac
evidence_dir="${script_dir}/evidence/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "${evidence_dir}" "${script_dir}/output_files"
trap 'printf "%s\n" "$?" > "${evidence_dir}/script-exit-status.txt"' EXIT
manifest() {
  (cd "${script_dir}" && sha256sum ../../rtl/ppc_icache.sv ppc_icache_storage.qsf ppc_icache_storage.qpf synthesize.sh)
}
manifest > "${evidence_dir}/source-before.sha256"
if [[ "${mode}" == local ]]; then
  quartus_sh --version > "${evidence_dir}/tool-versions.txt"
  compile=(quartus_map --read_settings_files=on --write_settings_files=off ppc_icache_storage -c ppc_icache_storage)
else
  docker image inspect --format 'id={{.Id}} repo_digests={{join .RepoDigests ","}}' "${image}" > "${evidence_dir}/image.txt"
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
if ! rg -q 'Implemented 0 input pins' "${evidence_dir}/build.log" ||
   ! rg -q 'Implemented 0 output pins' "${evidence_dir}/build.log" ||
   ! rg -q 'Design contains 374 virtual pins' "${evidence_dir}/build.log"; then
  echo "ERROR: expected all 374 cache ports to be virtual and zero physical I/O" >&2
  exit 4
fi
if ! rg -q 'Inferred altsyncram megafunction.*"data_mem_rtl_0"' "${evidence_dir}/build.log" ||
   rg -q 'RAM logic .*data_mem.*uninferred' "${evidence_dir}/build.log"; then
  echo "ERROR: cache data RAM inference was not confirmed" >&2
  exit 4
fi
python3 - "${evidence_dir}/ppc_icache_storage.map.rpt" <<'PY'
import sys
from pathlib import Path
rows = [[field.strip() for field in line.split(';')]
        for line in Path(sys.argv[1]).read_text().splitlines()]
assert any(len(row) > 9 and row[1].startswith('altsyncram:data_mem_rtl_0|')
           and row[3:9] == ['Simple Dual Port', '512', '256', '512', '256', '131072']
           for row in rows), 'missing full 512 x 256 data RAM in synthesis RAM Summary'
print('PASS: complete 131072-bit cache data array inferred as 512 x 256 synchronous-read RAM')
PY
