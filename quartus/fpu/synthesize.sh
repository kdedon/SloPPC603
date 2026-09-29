#!/usr/bin/env bash
# Standalone SS fpu_calc synthesis and post-map timing; no fitter run.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
image='theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70'
[[ "${1:---docker}" == --docker ]] || { echo 'usage: synthesize.sh [--docker]' >&2; exit 2; }

run() {
  local tech="$1"; shift
  docker run --rm --network none --user "$(id -u):$(id -g)" \
    --volume "${repo_dir}:/work" --workdir "/work/quartus/fpu/output_files/TECH${tech}/project" "${image}" \
    "/opt/intelFPGA_lite/quartus/bin/$@"
}

docker image inspect --format 'id={{.Id}} repo_digests={{join .RepoDigests ","}}' "${image}"
docker run --rm --network none --user "$(id -u):$(id -g)" --volume "${repo_dir}:/work" --workdir /work "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_sh --version
for tech in 0 1; do
  variant="${script_dir}/output_files/TECH${tech}"
  project="${variant}/project"
  mkdir -p "${project}" "${variant}/reports"
  rm -f "${variant}/reports"/* "${project}/output_files/ppc_fpu.map.rpt"
  "${repo_dir}/rtl/fpu/build_candidate.sh" "${tech}" "${variant}/generated"
  cp "${variant}/generated/fpu_calc.v" "${project}/fpu_calc.v"
  cp "${script_dir}/ppc_fpu.qpf" "${script_dir}/ppc_fpu.qsf" "${script_dir}/ppc_fpu.sdc" "${script_dir}/timing.tcl" "${project}/"
  manifest="${variant}/sources.sha256"
  (cd "${repo_dir}" && sha256sum \
    rtl/fpu/ss/base_pack.vhd rtl/fpu/ss/fpu_pack.vhd rtl/fpu/ss/fpu_mul.vhd \
    rtl/fpu/ss/fpu_div.vhd rtl/fpu/ss/fpu_calc.vhd rtl/fpu/ss_fpu_candidate.sv \
    rtl/fpu/build_candidate.sh rtl/fpu/canonicalize_candidate.py \
    "quartus/fpu/output_files/TECH${tech}/project/fpu_calc.v" quartus/fpu/ppc_fpu.qpf quartus/fpu/ppc_fpu.qsf \
    quartus/fpu/ppc_fpu.sdc quartus/fpu/timing.tcl quartus/fpu/synthesize.sh) > "${manifest}.before"
  run "${tech}" quartus_map --read_settings_files=on --write_settings_files=off \
    ppc_fpu -c ppc_fpu
  run "${tech}" quartus_sta -t timing.tcl
  (cd "${repo_dir}" && sha256sum \
    rtl/fpu/ss/base_pack.vhd rtl/fpu/ss/fpu_pack.vhd rtl/fpu/ss/fpu_mul.vhd \
    rtl/fpu/ss/fpu_div.vhd rtl/fpu/ss/fpu_calc.vhd rtl/fpu/ss_fpu_candidate.sv \
    rtl/fpu/build_candidate.sh rtl/fpu/canonicalize_candidate.py \
    "quartus/fpu/output_files/TECH${tech}/project/fpu_calc.v" quartus/fpu/ppc_fpu.qpf quartus/fpu/ppc_fpu.qsf \
    quartus/fpu/ppc_fpu.sdc quartus/fpu/timing.tcl quartus/fpu/synthesize.sh) > "${manifest}.after"
  cmp "${manifest}.before" "${manifest}.after"
  cp "${variant}/project/output_files/ppc_fpu.map.rpt" "${variant}/reports/"
  cp "${variant}/project/output_files/clocks.txt" "${variant}/project/output_files/fmax.txt" "${variant}/reports/"
  cp "${variant}/project/output_files/setup.txt" "${variant}/reports/"
  cp "${variant}/project/output_files/hold.txt" "${variant}/reports/"
  cp "${variant}/project/output_files/check_timing.txt" "${variant}/reports/"
  cp "${variant}/project/output_files/unconstrained.txt" "${variant}/reports/"
  echo "TECH${tech} synthesis summary:"
  grep -E 'Estimate of Logic utilization|Combinational ALUT usage|Dedicated logic registers|Total registers|Total block memory bits|Total DSP Blocks|Implemented .* pins|virtual pins' "${variant}/reports/ppc_fpu.map.rpt"
  cat "${variant}/reports/fmax.txt"
done
echo 'PASS: both TECH variants synthesized and post-map timed; no fitted area or timing-closure claim.'
