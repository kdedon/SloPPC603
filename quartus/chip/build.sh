#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
# --dual builds the core at DISPATCH_WIDTH 2; --fpu adds the FPU and
# --fpu-compact the COMPACT one; --lsu-pipe sets ENABLE_LSU_PIPE. --mister is
# the MiSTer core's processor: all four. --post-map stops after synthesis
# and ranks its setup paths into output_files/post-map.*.txt.
# --no-fpu removes the FPU from that configuration. --sys-mhz constrains
# the actual fit clock using a run-local copy of the canonical SDC.
# --jobs caps Quartus threads and Docker CPUs; containers use at most 8 GiB
# without swap. All project mutations and Quartus calls share one lock.
mode=local
dual=0
fpu=0
fpu_compact=0
lsu_pipe=0
post_map=0
quartus_jobs=2
sys_mhz=50
usage() { echo "usage: $0 [--docker] [--dual] [--fpu|--fpu-compact|--no-fpu] [--lsu-pipe] [--mister] [--post-map] [--jobs 1|2] [--sys-mhz 10..99]" >&2; exit 2; }
while (($#)); do
  case "$1" in
    local|--docker) mode="$1" ;;
    --dual) dual=1 ;;
    --fpu) fpu=1 ;;
    --fpu-compact) fpu=1; fpu_compact=1 ;;
    --no-fpu) fpu=0; fpu_compact=0 ;;
    --lsu-pipe) lsu_pipe=1 ;;
    --mister) dual=1; fpu=1; fpu_compact=1; lsu_pipe=1 ;;
    --post-map) post_map=1 ;;
    --jobs)
      shift
      [[ "${1:-}" =~ ^[12]$ ]] || usage
      quartus_jobs="$1"
      ;;
    --sys-mhz)
      shift
      [[ "${1:-}" =~ ^[1-9][0-9]$ ]] || usage
      sys_mhz="$1"
      ;;
    *) usage ;;
  esac
  shift
done
. "${script_dir}/../../ci/pins.env"
image="${QUARTUS_IMAGE:-${QUARTUS_IMAGE_PIN}}"
# Hold the lock before touching the project, including source regeneration.
exec 9>/tmp/ppc603e-quartus.lock
flock 9
python3 "${script_dir}/../check_disk_space.py" "${repo_dir}" /tmp
evidence_dir="${script_dir}/evidence/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "${evidence_dir}"
qsf="${script_dir}/ppc603e_chip.qsf"
cp "${qsf}" "${evidence_dir}/original.qsf"
on_exit() {
  status=$?
  cp "${evidence_dir}/original.qsf" "${qsf}"
  printf "%s\n" "${status}" > "${evidence_dir}/script-exit-status.txt"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
python3 "${script_dir}/../qsf_sources.py" "${script_dir}"
python3 "${script_dir}/../check_virtual_ports.py" "${script_dir}/ppc603e_measure.sv" "${qsf}"
run_sdc="${evidence_dir}/ppc603e_chip.run.sdc"
python3 - "${script_dir}/ppc603e_chip.sdc" "${run_sdc}" "${sys_mhz}" <<'PY'
from pathlib import Path
import re
import sys

canonical, target, mhz = sys.argv[1:]
period = 1000.0 / int(mhz)
source, matches = re.subn(
    r"(?m)^(create_clock -name core_clk -period )\S+",
    lambda match: f"{match[1]}{period:.6f}", Path(canonical).read_text(),
)
if matches != 1:
    raise SystemExit("ERROR: expected one canonical core clock constraint")
Path(target).write_text(f"# Run target: {mhz} MHz; all other constraints unchanged.\n" + source)
PY
run_sdc_relative="${run_sdc#"${script_dir}/"}"
sed -i '/^set_global_assignment -name NUM_PARALLEL_PROCESSORS /d; /^set_global_assignment -name SDC_FILE ppc603e_chip.sdc$/d' "${qsf}"
printf 'set_global_assignment -name NUM_PARALLEL_PROCESSORS %s\nset_global_assignment -name SDC_FILE %s\n' \
  "${quartus_jobs}" "${run_sdc_relative}" >> "${qsf}"
echo "Fit target: ${sys_mhz} MHz, ${quartus_jobs} Quartus threads; FPU=${fpu}, dual=${dual}, LSU pipeline=${lsu_pipe}"
if [[ "${lsu_pipe}" == 1 ]]; then
  echo 'set_global_assignment -name VERILOG_MACRO "PPC_LSU_PIPE=1"' >> "${qsf}"
fi
if [[ "${fpu_compact}" == 1 ]]; then
  echo 'set_parameter -name FPU_COMPACT 1' >> "${qsf}"
fi
if [[ "${lsu_pipe}" == 1 ]]; then
  # Its densest region does not route at standard routability.
  echo 'set_global_assignment -name FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION ALWAYS' >> "${qsf}"
fi
if [[ "${dual}" == 1 ]]; then
  echo 'set_global_assignment -name VERILOG_MACRO "PPC_DISPATCH_WIDTH=2"' >> "${qsf}"
fi
if [[ "${fpu}" == 1 ]]; then
  sed 's|^\.\./rtl/|../../rtl/|; s|^|set_global_assignment -name SYSTEMVERILOG_FILE |' "${repo_dir}/rtl/fpu_files.f" >> "${qsf}"
fi
echo "set_parameter -name ENABLE_FPU ${fpu}" >> "${qsf}"
cp "${qsf}" "${evidence_dir}/run.qsf"
manifest() {
  (
    cd "${script_dir}"
    while IFS= read -r source; do sha256sum "${source}"; done < files.f
    sha256sum files.f ppc603e_chip.qsf ppc603e_chip.qpf ppc603e_chip.sdc build.sh collect-reports.sh ../check_virtual_ports.py ../qsf_sources.py ../check_disk_space.py
    sha256sum "${run_sdc_relative}"
  )
}
manifest > "${evidence_dir}/source-before.sha256"
if [[ "${mode}" == local ]]; then
  if ! command -v quartus_sh >/dev/null 2>&1; then
    echo "ERROR: quartus_sh is not on PATH; use --docker with the reviewed image" | tee "${evidence_dir}/build.log" >&2
    exit 2
  fi
  quartus_sh --version > "${evidence_dir}/tool-versions.txt"
  run=()
  qbin=""
else
  docker image inspect --format 'id={{.Id}} repo_digests={{json .RepoDigests}}' "${image}" > "${evidence_dir}/image.txt"
  docker run --rm --network none --cpus "${quartus_jobs}" --memory 8g --memory-swap 8g "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_sh --version > "${evidence_dir}/tool-versions.txt"
  run=(docker run --rm --network none --cpus "${quartus_jobs}" --memory 8g --memory-swap 8g --user "$(id -u):$(id -g)" --volume "${repo_dir}:/work" --workdir /work/quartus/chip "${image}")
  qbin=/opt/intelFPGA_lite/quartus/bin/
fi
if [[ "${post_map}" == 1 ]]; then
  compile=("${run[@]}" bash -c "${qbin}quartus_map ppc603e_chip -c ppc603e_chip && ${qbin}quartus_sta -t ../post_map_paths.tcl ppc603e_chip ppc603e_chip output_files/post-map post_map")
else
  compile=("${run[@]}" "${qbin}quartus_sh" --flow compile ppc603e_chip -c ppc603e_chip)
fi
# Never collect a stale report left by an earlier attempt.
mkdir -p "${script_dir}/output_files"
rm -f "${script_dir}/output_files/ppc603e_chip."{flow,map,fit,sta}.rpt
set +e
(cd "${script_dir}" && "${compile[@]}") 2>&1 | tee "${evidence_dir}/build.log"
build_status=${PIPESTATUS[0]}
set -e
printf '%s\n' "${build_status}" > "${evidence_dir}/compile-exit-status.txt"
manifest > "${evidence_dir}/source-after.sha256"
for stage in flow map fit sta; do
  report="${script_dir}/output_files/ppc603e_chip.${stage}.rpt"
  if [[ -f "${report}" ]]; then cp "${report}" "${evidence_dir}/"; fi
done
echo "Evidence: ${evidence_dir}"
if ! cmp -s "${evidence_dir}/source-before.sha256" "${evidence_dir}/source-after.sha256"; then
  echo "ERROR: source changed during compilation; evidence is not a stable baseline" >&2
  exit 3
fi
if (( build_status != 0 )); then exit "${build_status}"; fi
if [[ "${post_map}" == 1 ]]; then
  echo "post-map paths: ${script_dir}/output_files/post-map.summary.txt"
  exit 0
fi
"${script_dir}/collect-reports.sh" "${evidence_dir}"
python3 "${script_dir}/../fit_summary.py" --name chip --dir "${evidence_dir}" --revision ppc603e_chip \
  --image "$([[ "${mode}" == --docker ]] && echo "${image}")" --core-mhz "${sys_mhz}" \
  --note "CPU isolation: FPU=${fpu}, COMPACT=${fpu_compact}, dual=${dual}, LSU pipeline=${lsu_pipe}" \
  --out "${evidence_dir}/summary.json"
cp "${evidence_dir}/summary.json" "${script_dir}/output_files/ppc603e_chip.summary.json"
