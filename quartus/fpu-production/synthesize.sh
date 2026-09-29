#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Map production FPU variants and run post-map STA. The fullfit variant also
# fits the 603e shell with clk_i on a real pin and times the fitted netlist.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
image='theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70'
usage='usage: synthesize.sh [--docker] [full|arith|full602|arith602|fullfit|all]'
[[ "${1:---docker}" == --docker ]] || { echo "${usage}" >&2; exit 2; }
variant_choice="${2:-all}"
case "${variant_choice}" in
  full|arith|full602|arith602|fullfit|all) ;;
  *) echo "${usage}" >&2; exit 2 ;;
esac
[[ $# -le 2 ]] || { echo "${usage}" >&2; exit 2; }
variants=(full arith full602 arith602)
if [[ "${variant_choice}" != all ]]; then variants=("${variant_choice}"); fi
run() {
  local variant="$1"; shift
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    --volume "${repo_dir}:/work" \
    --workdir "/work/quartus/fpu-production/output_files/${variant}/project" \
    "${image}" "/opt/intelFPGA_lite/quartus/bin/$@"
}

docker image inspect --format 'id={{.Id}} repo_digests={{join .RepoDigests ","}}' "${image}"
docker run --rm --network none --user "$(id -u):$(id -g)" \
  --volume "${repo_dir}:/work" --workdir /work "${image}" \
  /opt/intelFPGA_lite/quartus/bin/quartus_sh --version
for variant in "${variants[@]}"; do
  base_variant="${variant%602}"
  base_variant="${base_variant%fit}"
  fitted=0
  if [[ "${variant}" == *fit ]]; then fitted=1; fi
  project_dir="${script_dir}/output_files/${variant}/project"
  reports_dir="${script_dir}/output_files/${variant}/reports"
  mkdir -p "${project_dir}" "${reports_dir}"
  rm -f "${reports_dir}"/*
  cp "${script_dir}/${base_variant}/ppc_fpu.qpf" "${script_dir}/${base_variant}/ppc_fpu.qsf" \
    "${script_dir}/ppc_fpu.sdc" "${script_dir}/timing.tcl" "${project_dir}/"
  if [[ "${variant}" == *602 ]]; then
    echo 'set_parameter -name CPU_602 1' >> "${project_dir}/ppc_fpu.qsf"
  else
    echo 'set_parameter -name CPU_602 0' >> "${project_dir}/ppc_fpu.qsf"
  fi
  if (( fitted )); then
    # Route the clock from a real pin; all other ports stay virtual.
    sed -i '/VIRTUAL_PIN ON -to clk_i$/d' "${project_dir}/ppc_fpu.qsf"
    sed -i 's/create_timing_netlist -post_map/create_timing_netlist/' "${project_dir}/timing.tcl"
  fi
  sources=(rtl/ppc_pkg.sv rtl/fpu/ppc_fpu_pkg.sv rtl/fpu/ppc_fpu_arith.sv)
  if [[ "${base_variant}" == full ]]; then sources+=(rtl/fpu/ppc_fpu.sv); fi
  manifest="${script_dir}/output_files/${variant}/sources.sha256"
  project_inputs=(
    "quartus/fpu-production/output_files/${variant}/project/ppc_fpu.qpf"
    "quartus/fpu-production/output_files/${variant}/project/ppc_fpu.qsf"
    "quartus/fpu-production/output_files/${variant}/project/ppc_fpu.sdc"
    "quartus/fpu-production/output_files/${variant}/project/timing.tcl"
    quartus/fpu-production/synthesize.sh
  )
  (cd "${repo_dir}" && sha256sum "${sources[@]}" "${project_inputs[@]}") > "${manifest}.before"
  run "${variant}" quartus_map --read_settings_files=on --write_settings_files=off ppc_fpu -c ppc_fpu
  if (( fitted )); then
    run "${variant}" quartus_fit --read_settings_files=on --write_settings_files=off ppc_fpu -c ppc_fpu
  fi
  run "${variant}" quartus_sta -t timing.tcl
  (cd "${repo_dir}" && sha256sum "${sources[@]}" "${project_inputs[@]}") > "${manifest}.after"
  cmp "${manifest}.before" "${manifest}.after"
  if (( fitted )); then cp "${project_dir}/output_files/ppc_fpu.fit.summary" "${reports_dir}/"; fi
  for report in ppc_fpu.map.rpt clocks.txt check_timing.txt fmax.txt setup.txt hold.txt unconstrained.txt; do
    cp "${project_dir}/output_files/${report}" "${reports_dir}/"
  done
  for report in "${project_dir}"/output_files/stage_*.txt; do
    if [[ -f "${report}" ]]; then cp "${report}" "${reports_dir}/"; fi
  done
  map_report="${reports_dir}/ppc_fpu.map.rpt"
  expected_pins=0
  if (( fitted )); then expected_pins=1; fi
  if ! grep -Eq "Total pins +; ${expected_pins}( |;)" "${map_report}" ||
     ! grep -Eq 'Total virtual pins +; [1-9][0-9]*' "${map_report}"; then
    echo "ERROR: ${variant} did not map with ${expected_pins} physical pins" >&2
    exit 4
  fi
  echo "${variant} synthesis summary:"
  grep -E 'Estimate of Logic utilization|Combinational ALUT usage|Dedicated logic registers|Total registers|Total block memory bits|Total DSP Blocks|Total virtual pins|Total pins' "${map_report}"
  if (( fitted )); then
    echo "${variant} fitted summary:"
    grep -E 'Logic utilization|Total registers|Total block memory bits|Total DSP Blocks|Total pins' "${reports_dir}/ppc_fpu.fit.summary"
  fi
  python3 - "${reports_dir}" <<'PY'
import re
import sys
from pathlib import Path
reports = Path(sys.argv[1])
fmax = (reports / "fmax.txt").read_text()
setup = (reports / "setup.txt").read_text()
fm = re.search(r";\s*([0-9.]+) MHz\s*;\s*([0-9.]+) MHz\s*;\s*fpu_clk", fmax)
slack = re.search(r"Worst case slack is\s+(-?[0-9.]+)", setup)
if not fm or not slack:
    raise SystemExit("ERROR: could not parse Fmax and worst setup slack")
frequency = float(fm.group(1))
stage = "Post-fit" if "fit" in reports.parent.name else "Post-map"
print(f"{stage} Fmax: {frequency:.2f} MHz; 50 MHz: {'PASS' if frequency >= 50 else 'FAIL'}; 66 MHz: {'PASS' if frequency >= 66 else 'FAIL'}")
print(f"Worst setup slack at 20 ns: {float(slack.group(1)):.3f} ns")
print("Top setup paths:")
paths = [line for line in setup.splitlines() if re.match(r";\s*-?[0-9.]+\s*;", line)]
for line in paths[:10]:
    print(line)
PY
  if rg -n 'Warning \(|Critical Warning \(|Error \(' "${map_report}" "${reports_dir}/check_timing.txt"; then
    echo "Review warnings above for ${variant}."
  fi
done
echo 'PASS: production FPU variants measured; a fit variant reports fitted area and timing, other variants are post-map only.'
