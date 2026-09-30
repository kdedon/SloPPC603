#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Writes the corresponding source of a benchmark image: this repository at HEAD
# plus the fetched benchmark and runtime sources it was built from.
# Usage: source-archive.sh <out.tar.gz>
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out="$(realpath -m "${1:?usage: $0 <out.tar.gz>}")"
"${repo}/toolchain/demo/fetch-benchmarks.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
git -C "${repo}" archive --format=tar --prefix=ppc603e/ -o "${tmp}/source.tar" HEAD
tar --append -f "${tmp}/source.tar" -C "${repo}" --transform 's|^|ppc603e/|' toolchain/build/demo/src
gzip -9n < "${tmp}/source.tar" > "${out}"
echo "source archive: ${out}"
