#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Fetches every external input of the builds at its pin, checking each one:
#   dingusppc  DingusPPC at LAST_VERIFIED, beside the repository (commit id)
#   benchmarks benchmark and runtime sources (SHA-256 per file)
#   framework  MiSTer framework sys/ (SHA-256 over the tree)
# Nothing fetched is committed. With no argument, fetches all three.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
usage() { echo "usage: $0 [dingusppc] [benchmarks] [framework]" >&2; exit 2; }
parts=("$@")
if ((${#parts[@]} == 0)); then parts=(dingusppc benchmarks framework); fi

dingusppc() {
  local pin dest
  pin="$(sed -n "s/^LAST_VERIFIED = '\([0-9a-f]\{40\}\)'$/\1/p" "${repo}/sim/cosim/reference_checkout.py")"
  [[ -n "${pin}" ]] || { echo "setup: no LAST_VERIFIED pin" >&2; exit 1; }
  dest="${DINGUSPPC_DIR:-${repo}/../dingusppc}"
  if [[ ! -d "${dest}/.git" ]]; then
    git init -q "${dest}"
    git -C "${dest}" remote add origin https://github.com/dingusdev/dingusppc.git
  fi
  if [[ "$(git -C "${dest}" rev-parse -q --verify HEAD 2>/dev/null)" != "${pin}" ]]; then
    git -C "${dest}" fetch -q --depth 1 origin "${pin}"
    git -C "${dest}" checkout -q --detach FETCH_HEAD
  fi
  if [[ "$(git -C "${dest}" rev-parse HEAD)" != "${pin}" || -n "$(git -C "${dest}" status --porcelain)" ]]; then
    echo "setup: ${dest} is not a clean checkout of ${pin}" >&2
    exit 1
  fi
  echo "setup: DingusPPC ${pin} in ${dest}"
}

for part in "${parts[@]}"; do
  case "${part}" in
    dingusppc) dingusppc ;;
    benchmarks) "${repo}/toolchain/demo/fetch-benchmarks.sh" ;;
    framework) "${repo}/mister/fetch-framework.sh" ;;
    *) usage ;;
  esac
done
