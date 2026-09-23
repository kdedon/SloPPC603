#!/usr/bin/env bash
# Report endpoints from an existing completed fit; never synthesize or fit.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
image="${QUARTUS_IMAGE:-theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70}"
case "${1:-local}" in
  local)
    cd "${script_dir}"
    exec quartus_sta --do_report_timing ppc603e_integrated -c ppc603e_integrated
    ;;
  --docker)
    exec docker run --rm --network none --user "$(id -u):$(id -g)" \
      --volume "${repo_dir}:/work" --workdir /work/quartus/integrated \
      "${image}" /opt/intelFPGA_lite/quartus/bin/quartus_sta \
      --do_report_timing ppc603e_integrated -c ppc603e_integrated
    ;;
  *) echo "usage: $0 [--docker]" >&2; exit 2 ;;
esac
