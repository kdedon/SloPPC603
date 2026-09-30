#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Quartus analysis and elaboration of ppc602_measure, optionally with the
# FPU (FULL or COMPACT), in the pinned container. No synthesis or fit.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "${script_dir}/../.." && pwd)"
. "${script_dir}/../../ci/pins.env"
image="${QUARTUS_IMAGE:-${QUARTUS_IMAGE_PIN}}"
fpu=0
compact=0
case "${1:-}" in
  "") ;;
  --fpu) fpu=1 ;;
  --fpu-compact) fpu=1; compact=1 ;;
  *) echo "usage: $0 [--fpu|--fpu-compact]" >&2; exit 2 ;;
esac
revision=ppc602_chip_analysis
qsf="${script_dir}/${revision}.qsf"
trap 'rm -f "${qsf}"' EXIT
cp "${script_dir}/ppc602_chip.qsf" "${qsf}"
if [[ "${fpu}" == 1 ]]; then
  sed 's|^\.\./rtl/|../../rtl/|; s|^|set_global_assignment -name SYSTEMVERILOG_FILE |' \
    "${repo_dir}/rtl/fpu_files.f" >> "${qsf}"
  echo 'set_parameter -name ENABLE_FPU 1' >> "${qsf}"
  echo "set_parameter -name FPU_COMPACT ${compact}" >> "${qsf}"
fi
docker run --rm --network none --user "$(id -u):$(id -g)" --volume "${repo_dir}:/work" \
  --workdir /work/quartus/chip602 "${image}" \
  /opt/intelFPGA_lite/quartus/bin/quartus_map ppc602_chip -c "${revision}" \
  --analysis_and_elaboration
