#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Fetches the MiSTer framework (sys/ of Template_MiSTer, GPL-2.0) at a pinned
# commit into mister/sys and checks the tree against a known digest: the
# SHA-256 of `sha256sum` over every file, sorted by path.
set -euo pipefail
commit=3ea1134cf05d62c2b1db30362277a823d739ced2
digest=d1fe0cfea73e7870a28c683ddcac427f09951a2d69aaa666dd61b11a95e77170
url="https://github.com/MiSTer-devel/Template_MiSTer/archive/${commit}.tar.gz"
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

tree_digest() {
  (cd "$1" && find sys -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d' ' -f1)
}

if [[ -d "${here}/sys" && "$(tree_digest "${here}")" == "${digest}" ]]; then
  echo "fetch-framework: sys/ verified at ${commit}"
  exit 0
fi
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
curl -fsSL "${url}" | tar -xz -C "${tmp}"
src="${tmp}/Template_MiSTer-${commit}"
got="$(tree_digest "${src}")"
if [[ "${got}" != "${digest}" ]]; then
  echo "fetch-framework: digest mismatch: ${got}" >&2
  exit 1
fi
rm -rf "${here}/sys"
cp -r "${src}/sys" "${here}/sys"
echo "fetch-framework: sys/ fetched and verified at ${commit}"
