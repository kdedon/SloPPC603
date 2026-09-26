#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/.." && pwd)"
mode="${1:-local}"
image="${QUARTUS_IMAGE:-theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70}"

case "${mode}" in local|--docker) ;; *) echo "usage: $0 [--docker]" >&2; exit 2 ;; esac
python3 "${script_dir}/qsf_sources.py" "${script_dir}"
python3 "${script_dir}/check_virtual_ports.py" "${script_dir}/ppc_core_measure.sv" "${script_dir}/ppc603e_core.qsf"
mkdir -p "${script_dir}/evidence"

case "${mode}" in
  local)
    if ! command -v quartus_sh >/dev/null 2>&1; then
      echo "ERROR: quartus_sh is not on PATH; use --docker or install a reviewed Quartus version" >&2
      exit 2
    fi
    quartus_sh --version > "${script_dir}/evidence/tool-versions.txt"
    (
      cd "${script_dir}"
      quartus_sh --flow compile ppc603e_core -c ppc603e_core
    )
    ;;
  --docker)
    docker image inspect --format 'id={{.Id}} repo_digests={{join .RepoDigests ","}}' "${image}" \
      > "${script_dir}/evidence/image.txt"
    docker run --rm \
      --user "$(id -u):$(id -g)" \
      --volume "${repo_dir}:/work" \
      --workdir /work/quartus \
      "${image}" \
      /opt/intelFPGA_lite/quartus/bin/quartus_sh --flow compile \
      ppc603e_core -c ppc603e_core
    docker run --rm "${image}" \
      /opt/intelFPGA_lite/quartus/bin/quartus_sh --version \
      > "${script_dir}/evidence/tool-versions.txt"
    ;;
  *)
    echo "usage: $0 [--docker]" >&2
    exit 2
    ;;
esac

"${script_dir}/collect-reports.sh"
