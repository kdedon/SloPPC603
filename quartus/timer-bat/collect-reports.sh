#!/usr/bin/env bash
set -euo pipefail
evidence_dir="${1:?usage: collect-reports.sh EVIDENCE_DIRECTORY}"
for stage in flow map fit sta; do
  report="${evidence_dir}/ppc603e_timer_bat.${stage}.rpt"
  [[ -s "${report}" ]] || { echo "ERROR: missing ${report}" >&2; exit 1; }
done
map_report="${evidence_dir}/ppc603e_timer_bat.map.rpt"
# The direct retirement packet plus bus/control ports must remain externally
# observable. An exact pin count is recorded by Quartus, not guessed here.
if ! rg -q 'Implemented 0 input pins' "${map_report}" ||
   ! rg -q 'Implemented 0 output pins' "${map_report}" ||
   ! rg -q 'Design contains [1-9][0-9]* virtual pins' "${map_report}"; then
  echo "ERROR: expected virtual measurement ports and zero physical I/O" >&2
  exit 1
fi
rg -n 'Logic utilization|Total registers|Total block memory bits|Total RAM Blocks|DSP block|Implemented [0-9]+ (input|output) pins|Design contains [0-9]+ virtual pins|Worst-case Slack|Worst-case (setup|hold) slack|Timing requirements not met|Timing requirements were met|Unconstrained' "${evidence_dir}"/*.rpt > "${evidence_dir}/summary.txt" || true
echo "Collected timer-BAT-subset reports; inspect RAM inference and timing before making fit or frequency claims."
