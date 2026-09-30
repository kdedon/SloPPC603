#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Quartus analysis and elaboration of ppc602_measure, optionally with the
# FPU (FULL or COMPACT), in the pinned container. No synthesis or fit. The
# project is copied into a scratch subdirectory, removed afterwards.
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
work="analysis-$$"
dir="${script_dir}/${work}"
trap 'rm -rf "${dir}"' EXIT
mkdir -p "${dir}"
sed 's|\.\./\.\./rtl/|../../../rtl/|; s|FILE ppc602_measure\.sv|FILE ../ppc602_measure.sv|; s|SDC_FILE |SDC_FILE ../|' \
  "${script_dir}/ppc602_chip.qsf" > "${dir}/ppc602_chip.qsf"
if [[ "${fpu}" == 1 ]]; then
  sed 's|^\.\./rtl/|../../../rtl/|; s|^|set_global_assignment -name SYSTEMVERILOG_FILE |' \
    "${repo_dir}/rtl/fpu_files.f" >> "${dir}/ppc602_chip.qsf"
  echo 'set_parameter -name ENABLE_FPU 1' >> "${dir}/ppc602_chip.qsf"
  echo "set_parameter -name FPU_COMPACT ${compact}" >> "${dir}/ppc602_chip.qsf"
fi
cp "${script_dir}/ppc602_chip.qpf" "${dir}/"
docker run --rm --network none --user "$(id -u):$(id -g)" --volume "${repo_dir}:/work" \
  --workdir "/work/quartus/chip602/${work}" "${image}" \
  /opt/intelFPGA_lite/quartus/bin/quartus_map ppc602_chip -c ppc602_chip \
  --analysis_and_elaboration
