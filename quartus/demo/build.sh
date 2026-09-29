#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Compiles the demonstration system in the reviewed Quartus image and prints
# resource use and slow-corner Fmax. --clean deletes the outputs afterwards.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
image="${QUARTUS_IMAGE:-theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70}"
python3 "${script_dir}/../qsf_sources.py" --check "${script_dir}"
rm -rf "${script_dir}/output_files"
status=0
docker run --rm --network none --user "$(id -u):$(id -g)" --volume "${repo_dir}:/work" \
  --workdir /work/quartus/demo "${image}" \
  /opt/intelFPGA_lite/quartus/bin/quartus_sh --flow compile ppc603e_demo -c ppc603e_demo \
  > "${script_dir}/output_files.log" 2>&1 || status=$?
out="${script_dir}/output_files"
if [[ -f "${out}/ppc603e_demo.fit.summary" ]]; then
  grep -E "Logic utilization|Total registers|Total block memory bits|Total RAM Blocks|Total DSP Blocks" \
    "${out}/ppc603e_demo.fit.summary" || true
fi
if [[ -f "${out}/ppc603e_demo.sta.rpt" ]]; then
  grep -A6 "; Slow 1100mV 85C Model Fmax Summary" "${out}/ppc603e_demo.sta.rpt" | grep -E "MHz" || true
  grep -A4 "Slow 1100mV 85C Model Setup Summary" "${out}/ppc603e_demo.sta.rpt" | grep -E "^; clk" || true
fi
echo "quartus exit status ${status}"
if [[ "${1:-}" == --clean ]]; then
  rm -rf "${script_dir}/db" "${script_dir}/incremental_db" "${out}" "${script_dir}/output_files.log" "${script_dir}"/*.qws
fi
exit "${status}"
