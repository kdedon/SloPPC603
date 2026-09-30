#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Report endpoints from an existing completed fit; never synthesize or fit.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
. "${script_dir}/../../ci/pins.env"
image="${QUARTUS_IMAGE:-${QUARTUS_IMAGE_PIN}}"
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
