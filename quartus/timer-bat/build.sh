#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
mode="${1:-local}"
. "${script_dir}/../../ci/pins.env"
image="${QUARTUS_IMAGE:-${QUARTUS_IMAGE_PIN}}"
case "${mode}" in local|--docker) ;; *) echo "usage: $0 [--docker]" >&2; exit 2 ;; esac
python3 "${script_dir}/../qsf_sources.py" "${script_dir}"
python3 "${script_dir}/../check_virtual_ports.py" "${script_dir}/ppc_timer_bat_measure.sv" "${script_dir}/ppc603e_timer_bat.qsf"
evidence_dir="${script_dir}/evidence/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "${evidence_dir}"
trap 'printf "%s\n" "$?" > "${evidence_dir}/script-exit-status.txt"' EXIT
manifest() {
  (
    cd "${script_dir}"
    while IFS= read -r source; do sha256sum "${source}"; done < files.f
    sha256sum files.f ppc603e_timer_bat.qsf ppc603e_timer_bat.qpf ppc603e_timer_bat.sdc build.sh collect-reports.sh ../check_virtual_ports.py ../qsf_sources.py
  )
}
manifest > "${evidence_dir}/source-before.sha256"
if [[ "${mode}" == local ]]; then
  if ! command -v quartus_sh >/dev/null 2>&1; then
    echo "ERROR: quartus_sh is not on PATH; use --docker with the reviewed image" | tee "${evidence_dir}/build.log" >&2
    exit 2
  fi
  quartus_sh --version > "${evidence_dir}/tool-versions.txt"
  compile=(quartus_sh --flow compile ppc603e_timer_bat -c ppc603e_timer_bat)
else
  docker image inspect --format 'id={{.Id}} repo_digests={{json .RepoDigests}}' "${image}" > "${evidence_dir}/image.txt"
  docker run --rm --network none "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_sh --version > "${evidence_dir}/tool-versions.txt"
  compile=(docker run --rm --network none --user "$(id -u):$(id -g)" --volume "${repo_dir}:/work" --workdir /work/quartus/timer-bat "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_sh --flow compile ppc603e_timer_bat -c ppc603e_timer_bat)
fi
# Never collect a stale report left by an earlier attempt.
mkdir -p "${script_dir}/output_files"
rm -f "${script_dir}/output_files/ppc603e_timer_bat."{flow,map,fit,sta}.rpt
set +e
(cd "${script_dir}" && "${compile[@]}") 2>&1 | tee "${evidence_dir}/build.log"
build_status=${PIPESTATUS[0]}
set -e
printf '%s\n' "${build_status}" > "${evidence_dir}/compile-exit-status.txt"
manifest > "${evidence_dir}/source-after.sha256"
for stage in flow map fit sta; do
  report="${script_dir}/output_files/ppc603e_timer_bat.${stage}.rpt"
  if [[ -f "${report}" ]]; then cp "${report}" "${evidence_dir}/"; fi
done
echo "Evidence: ${evidence_dir}"
if ! cmp -s "${evidence_dir}/source-before.sha256" "${evidence_dir}/source-after.sha256"; then
  echo "ERROR: source changed during compilation; evidence is not a stable baseline" >&2
  exit 3
fi
if (( build_status != 0 )); then exit "${build_status}"; fi
"${script_dir}/collect-reports.sh" "${evidence_dir}"
python3 "${script_dir}/../fit_summary.py" --name timer-bat --dir "${evidence_dir}" --revision ppc603e_timer_bat \
  --image "$([[ "${mode}" == --docker ]] && echo "${image}")" --out "${evidence_dir}/summary.json"
cp "${evidence_dir}/summary.json" "${script_dir}/output_files/ppc603e_timer_bat.summary.json"
