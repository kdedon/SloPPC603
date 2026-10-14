#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Map production FPU variants and run post-map STA. A *fit variant also fits
# the shell with clk_i on a real pin and times the fitted netlist. The compact
# variants measure the FPU_IMPL=COMPACT unit, ppc_fpu_compact.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
. "${script_dir}/../../ci/pins.env"
image="${QUARTUS_IMAGE:-${QUARTUS_IMAGE_PIN}}"
usage='usage: synthesize.sh [--docker] [full|arith|full602|arith602|fullfit|full602fit|compact|compact602|arithcompact|arithcompact602|compactfit|compact602fit|all] [--clock-mhz N]'
if (( $# )); then
  [[ "$1" == --docker ]] || { echo "${usage}" >&2; exit 2; }
  shift
fi
variant_choice=all
variant_seen=0
clock_mhz=50
while (( $# )); do
  case "$1" in
    --clock-mhz)
      shift
      [[ "${1:-}" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "${usage}" >&2; exit 2; }
      clock_mhz="$1"
      ;;
    *)
      (( variant_seen == 0 )) || { echo "${usage}" >&2; exit 2; }
      variant_choice="$1"
      variant_seen=1
      ;;
  esac
  shift
done
case "${variant_choice}" in
  full|arith|full602|arith602|fullfit|full602fit) ;;
  compact|compact602|arithcompact|arithcompact602|compactfit|compact602fit|all) ;;
  *) echo "${usage}" >&2; exit 2 ;;
esac
clock_period="$(python3 - "${clock_mhz}" <<'PY'
from decimal import Decimal
import sys
frequency = Decimal(sys.argv[1])
if frequency <= 0:
    raise SystemExit('ERROR: --clock-mhz must be positive')
period = Decimal(1000) / frequency
if period < Decimal('0.000000001'):
    raise SystemExit('ERROR: clock period is below the report precision')
print(f'{period:.9f}')
PY
)"
core_mhz_args=()
core_mhz="$(python3 - "${clock_mhz}" <<'PY'
from decimal import Decimal
import sys
frequency = Decimal(sys.argv[1])
if frequency == frequency.to_integral_value():
    print(int(frequency))
PY
)"
if [[ -n "${core_mhz}" ]]; then core_mhz_args=(--core-mhz "${core_mhz}"); fi
variants=(full arith full602 arith602 compact arithcompact compact602 arithcompact602)
if [[ "${variant_choice}" != all ]]; then variants=("${variant_choice}"); fi
# Hold the shared lock through project generation, map, fit and STA so another
# invocation cannot overwrite this variant's files between Quartus commands.
exec {quartus_lock_fd}>/tmp/ppc603e-quartus.lock
flock "${quartus_lock_fd}"
run() {
  local variant="$1"; shift
  docker run --rm --network none --cpus 2 --memory 8g --memory-swap 8g --user "$(id -u):$(id -g)" \
    --volume "${repo_dir}:/work" \
    --workdir "/work/quartus/fpu-production/output_files/${variant}/project" \
    "${image}" "/opt/intelFPGA_lite/quartus/bin/$@"
}

docker image inspect --format 'id={{.Id}} repo_digests={{json .RepoDigests}}' "${image}"
docker run --rm --network none --cpus 2 --memory 8g --memory-swap 8g --user "$(id -u):$(id -g)" \
  --volume "${repo_dir}:/work" --workdir /work "${image}" \
  /opt/intelFPGA_lite/quartus/bin/quartus_sh --version
for variant in "${variants[@]}"; do
  python3 "${script_dir}/../check_disk_space.py" "${repo_dir}" /tmp
  base_variant="${variant%fit}"
  base_variant="${base_variant%602}"
  fitted=0
  if [[ "${variant}" == *fit ]]; then fitted=1; fi
  project_dir="${script_dir}/output_files/${variant}/project"
  reports_dir="${script_dir}/output_files/${variant}/reports"
  mkdir -p "${project_dir}" "${reports_dir}"
  rm -f "${reports_dir}"/*
  cp "${script_dir}/${base_variant}/ppc_fpu.qpf" "${script_dir}/${base_variant}/ppc_fpu.qsf" \
    "${script_dir}/ppc_fpu.sdc" "${script_dir}/timing.tcl" "${project_dir}/"
  # Change only the generated clock period; retain every boundary and I/O rule.
  python3 - "${project_dir}/ppc_fpu.sdc" "${clock_period}" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
text, count = re.subn(
    r'(?m)^(create_clock -name fpu_clk -period )\S+( \[get_ports \{clk_i\}\])$',
    lambda match: match[1] + sys.argv[2] + match[2], path.read_text())
if count != 1:
    raise SystemExit('ERROR: expected exactly one fpu_clk constraint')
path.write_text(text)
PY
  echo "${variant} requested clock: ${clock_mhz} MHz (${clock_period} ns)"
  if [[ "${variant}" == *602 || "${variant}" == *602fit ]]; then
    echo 'set_parameter -name CPU_602 1' >> "${project_dir}/ppc_fpu.qsf"
  else
    echo 'set_parameter -name CPU_602 0' >> "${project_dir}/ppc_fpu.qsf"
  fi
  if (( fitted )); then
    # Route the clock from a real pin; all other ports stay virtual.
    echo 'set_global_assignment -name TIMEQUEST_MULTICORNER_ANALYSIS ON' >> "${project_dir}/ppc_fpu.qsf"
    sed -i '/VIRTUAL_PIN ON -to clk_i$/d' "${project_dir}/ppc_fpu.qsf"
    sed -i 's/create_timing_netlist -post_map/create_timing_netlist/' "${project_dir}/timing.tcl"
  fi
  if (( fitted )) && [[ "${base_variant}" == full || "${base_variant}" == compact ]]; then
    # Fit the shell behind one boundary register per port.
    sed -i -E 's/TOP_LEVEL_ENTITY ppc_fpu(_compact)?$/TOP_LEVEL_ENTITY ppc_fpu_measure/' "${project_dir}/ppc_fpu.qsf"
    echo 'set_global_assignment -name SYSTEMVERILOG_FILE ../../../ppc_fpu_measure.sv' >> "${project_dir}/ppc_fpu.qsf"
    if [[ "${base_variant}" == compact ]]; then
      echo 'set_parameter -name COMPACT 1' >> "${project_dir}/ppc_fpu.qsf"
    fi
  fi
  sources=(rtl/ppc_pkg.sv rtl/fpu/ppc_fpu_pkg.sv rtl/fpu/ppc_fpu_arith_pkg.sv rtl/fpu/ppc_fpu_unpack.sv
    rtl/fpu/ppc_fpu_multiplier.sv rtl/fpu/ppc_fpu_align_plan.sv rtl/fpu/ppc_fpu_aligner.sv
    rtl/fpu/ppc_fpu_adder.sv rtl/fpu/ppc_fpu_convert.sv rtl/fpu/ppc_fpu_rounder.sv
    rtl/fpu/ppc_fpu_divider.sv rtl/fpu/ppc_fpu_arith.sv)
  if [[ "${base_variant}" == compact || "${base_variant}" == arithcompact ]]; then
    sources+=(rtl/fpu/ppc_fpu_arith_compact.sv)
  fi
  if [[ "${base_variant}" == full ]]; then sources+=(rtl/fpu/ppc_fpu_shell_pkg.sv rtl/ppc_ram_lut.sv rtl/fpu/ppc_fpu_fprs.sv rtl/fpu/ppc_fpu.sv); fi
  if [[ "${base_variant}" == compact ]]; then sources+=(rtl/fpu/ppc_fpu_shell_pkg.sv rtl/ppc_ram_lut.sv rtl/fpu/ppc_fpu_compact.sv); fi
  if (( fitted )) && [[ "${base_variant}" == full || "${base_variant}" == compact ]]; then
    sources+=(quartus/fpu-production/ppc_fpu_measure.sv)
  fi
  manifest="${script_dir}/output_files/${variant}/sources.sha256"
  project_inputs=(
    "quartus/fpu-production/output_files/${variant}/project/ppc_fpu.qpf"
    "quartus/fpu-production/output_files/${variant}/project/ppc_fpu.qsf"
    "quartus/fpu-production/output_files/${variant}/project/ppc_fpu.sdc"
    "quartus/fpu-production/output_files/${variant}/project/timing.tcl"
    quartus/fpu-production/synthesize.sh
    quartus/check_disk_space.py
  )
  (cd "${repo_dir}" && sha256sum "${sources[@]}" "${project_inputs[@]}") > "${manifest}.before"
  run "${variant}" quartus_map --read_settings_files=on --write_settings_files=off ppc_fpu -c ppc_fpu
  if (( fitted )); then
    run "${variant}" quartus_fit --read_settings_files=on --write_settings_files=off ppc_fpu -c ppc_fpu
    run "${variant}" quartus_sta ppc_fpu -c ppc_fpu
    # Save all-corner STA before the custom single-corner diagnostic session.
    cp "${project_dir}/output_files/ppc_fpu.fit.summary" "${project_dir}/output_files/ppc_fpu.fit.rpt" \
      "${project_dir}/output_files/ppc_fpu.sta.rpt" "${project_dir}/output_files/ppc_fpu.sta.summary" "${reports_dir}/"
    # No setup.txt exists here yet, so fit_summary uses the all-corner reports.
    python3 "${script_dir}/../fit_summary.py" --name "fpu-${variant}" --dir "${reports_dir}" --revision ppc_fpu \
      --image "${image}" "${core_mhz_args[@]}" --note "requested clock ${clock_mhz} MHz; all-corner fitted STA" \
      --out "${reports_dir}/summary.json"
  fi
  run "${variant}" quartus_sta -t timing.tcl
  (cd "${repo_dir}" && sha256sum "${sources[@]}" "${project_inputs[@]}") > "${manifest}.after"
  cmp "${manifest}.before" "${manifest}.after"
  for report in ppc_fpu.map.rpt clocks.txt check_timing.txt fmax.txt setup.txt setup_endpoints.txt hold.txt unconstrained.txt; do
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
    echo "${variant} fitted ALMs by entity (ALMs needed, registers, MLAB bits, M10K bits, DSP):"
    python3 - "${reports_dir}/ppc_fpu.fit.rpt" <<'PY'
import re
import sys
text = open(sys.argv[1], encoding="latin-1").read()
lines = text.split("; Fitter Resource Utilization by Entity", 1)[1].splitlines()
start = next(i for i, line in enumerate(lines) if "Compilation Hierarchy Node" in line)
header = [cell.strip() for cell in lines[start].strip().strip(";").split(";")]
wanted = ["ALMs needed", "Dedicated Logic Registers", "Block Memory Bits", "M10Ks", "DSP Blocks"]
columns = [next(i for i, cell in enumerate(header) if cell.startswith(name)) for name in wanted]
# A measurement wrapper adds one hierarchy level.
depth = 12 if "|ppc_fpu_measure" in lines[start + 2] else 9
for line in lines[start + 2:]:
    if not line.startswith(";"):
        break
    cells = line.strip().strip(";").split(";")
    name = cells[0].rstrip()
    if len(name) - len(name.lstrip()) > depth:
        continue
    print(f"{name[:56]:56}" + "".join(f"{cells[i].strip():>14}" for i in columns))
PY
  fi
  python3 - "${reports_dir}" "${clock_mhz}" "${clock_period}" <<'PY'
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
print(f"{stage} single-corner diagnostic Fmax: {frequency:.2f} MHz; >=50 MHz: {frequency >= 50}; >=66 MHz: {frequency >= 66}")
print(f"Worst setup slack at {sys.argv[3]} ns ({sys.argv[2]} MHz requested): {float(slack.group(1)):.3f} ns")
if stage == 'Post-fit':
    print('This diagnostic corner does not establish closure; all-corner results are in ppc_fpu.sta.summary and summary.json.')
else:
    print('Post-map single-corner diagnostics do not establish fitted timing closure.')
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
