#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# List failing setup endpoints of an existing fit at another clock period
# (default 15.152 ns, 66 MHz); the project SDC stays the gate of record.
# Usage: report-target-paths.sh <integrated|timer-bat|translated|chip|chip602> [period_ns] [--docker]
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
. "${script_dir}/../ci/pins.env"
image="${QUARTUS_IMAGE:-${QUARTUS_IMAGE_PIN}}"
top="${1:?usage: $0 <integrated|timer-bat|translated|chip|chip602> [period_ns] [--docker]}"
period="15.152"
mode=local
for arg in "${@:2}"; do
  case "${arg}" in --docker) mode=docker ;; *) period="${arg}" ;; esac
done
case "${top}" in
  integrated) revision=ppc603e_integrated ;;
  timer-bat) revision=ppc603e_timer_bat ;;
  translated) revision=ppc603e_translated ;;
  chip) revision=ppc603e_chip ;;
  chip602) revision=ppc602_chip ;;
  *) echo "unknown top ${top}" >&2; exit 2 ;;
esac
out="output_files/${revision}.target-paths.tsv"
args=(-t ../target_paths.tcl "${revision}" "${period}" "${out}")
rm -f "${script_dir}/${top}/${out}.worst.txt"
if [[ "${mode}" == local ]]; then
  (cd "${script_dir}/${top}" && quartus_sta "${args[@]}")
else
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    --volume "${repo_dir}:/work" --workdir "/work/quartus/${top}" \
    "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_sta "${args[@]}"
fi
python3 "${script_dir}/group_paths.py" "${script_dir}/${top}/${out}"
echo "boundary paths (corner, class, slack, from, to):"
cat "${script_dir}/${top}/${out}.boundary.txt"
python3 "${script_dir}/fit_summary.py" --name "${top}" --dir "${script_dir}/${top}/output_files" \
  --revision "${revision}" --target-period "${period}" --image "${image}" \
  --out "${script_dir}/${top}/output_files/${revision}.summary.json"
