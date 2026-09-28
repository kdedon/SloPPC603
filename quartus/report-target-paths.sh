#!/usr/bin/env bash
# List failing setup endpoints of an existing fit at another clock period
# (default 15.152 ns, 66 MHz); the project SDC stays the gate of record.
# Usage: report-target-paths.sh <integrated|timer-bat|translated> [period_ns] [--docker]
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
image="${QUARTUS_IMAGE:-theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70}"
top="${1:?usage: $0 <integrated|timer-bat|translated> [period_ns] [--docker]}"
period="15.152"
mode=local
for arg in "${@:2}"; do
  case "${arg}" in --docker) mode=docker ;; *) period="${arg}" ;; esac
done
case "${top}" in
  integrated) revision=ppc603e_integrated ;;
  timer-bat) revision=ppc603e_timer_bat ;;
  translated) revision=ppc603e_translated ;;
  *) echo "unknown top ${top}" >&2; exit 2 ;;
esac
out="output_files/${revision}.target-paths.tsv"
args=(-t ../target_paths.tcl "${revision}" "${period}" "${out}")
if [[ "${mode}" == local ]]; then
  (cd "${script_dir}/${top}" && quartus_sta "${args[@]}")
else
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    --volume "${repo_dir}:/work" --workdir "/work/quartus/${top}" \
    "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_sta "${args[@]}"
fi
python3 "${script_dir}/group_paths.py" "${script_dir}/${top}/${out}"
