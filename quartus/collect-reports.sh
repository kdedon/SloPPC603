#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
output_dir="${script_dir}/output_files"
evidence_dir="${script_dir}/evidence"

mkdir -p "${evidence_dir}"
map_report="${output_dir}/ppc603e_core.map.rpt"
if ! rg -q 'Design contains 35 virtual pins' "${map_report}" ||
   ! rg -q 'Implemented 0 input pins' "${map_report}" ||
   ! rg -q 'Implemented 0 output pins' "${map_report}"; then
  echo "ERROR: expected 35 virtual pins and zero physical package pins" >&2
  exit 1
fi

for report in \
  "${output_dir}/ppc603e_core.flow.rpt" \
  "${output_dir}/ppc603e_core.map.rpt" \
  "${output_dir}/ppc603e_core.fit.rpt" \
  "${output_dir}/ppc603e_core.sta.rpt"; do
  if [[ ! -s "${report}" ]]; then
    echo "ERROR: expected nonempty report is missing: ${report}" >&2
    exit 1
  fi
  cp "${report}" "${evidence_dir}/"
done

(
  cd "${evidence_dir}"
  rg -n \
    'Logic utilization|Total registers|Total block memory bits|Total RAM Blocks|DSP block|Implemented [0-9]+ (input|output) pins|Design contains [0-9]+ virtual pins|Worst-case Slack|Worst-case (setup|hold) slack|Timing requirements not met|Timing requirements were met|Unconstrained' \
    ./*.rpt > summary.txt || true
)

(
  cd "${script_dir}/.."
  sha256sum rtl/*.sv rtl/files.f quartus/ppc_core_measure.sv \
    quartus/ppc603e_core.qsf quartus/ppc603e_core.qpf quartus/ppc603e_core.sdc \
    > "${evidence_dir}/source-sha256.txt"
)

echo "Copied Quartus flow, fit, and timing reports to ${evidence_dir}"
