#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
set -euo pipefail
evidence_dir="${1:?usage: collect-reports.sh EVIDENCE_DIRECTORY}"
for stage in flow map fit sta; do
  report="${evidence_dir}/ppc603e_translated.${stage}.rpt"
  [[ -s "${report}" ]] || { echo "ERROR: missing ${report}" >&2; exit 1; }
done
map_report="${evidence_dir}/ppc603e_translated.map.rpt"
# The direct retirement packet plus bus/control ports must remain externally
# observable. An exact pin count is recorded by Quartus, not guessed here.
if ! grep -Eq 'Implemented 0 input pins' "${map_report}" ||
   ! grep -Eq 'Implemented 0 output pins' "${map_report}" ||
   ! grep -Eq 'Design contains [1-9][0-9]* virtual pins' "${map_report}"; then
  echo "ERROR: expected virtual measurement ports and zero physical I/O" >&2
  exit 1
fi
grep -En 'Logic utilization|Total registers|Total block memory bits|Total RAM Blocks|DSP block|Implemented [0-9]+ (input|output) pins|Design contains [0-9]+ virtual pins|Worst-case Slack|Worst-case (setup|hold) slack|Timing requirements not met|Timing requirements were met|Unconstrained' "${evidence_dir}"/*.rpt > "${evidence_dir}/summary.txt" || true
echo "Collected translated MVP reports; inspect RAM inference and timing before making fit or frequency claims."
