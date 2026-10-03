#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
. "${repo_dir}/ci/pins.env"
image="${TOOLCHAIN_IMAGE:-${TOOLCHAIN_IMAGE_PIN}}"
evidence_dir="${repo_dir}/toolchain/evidence"

docker build --pull=false --provenance=false --build-arg SOURCE_DATE_EPOCH=0 \
  --build-arg "BASE_IMAGE=${TOOLCHAIN_BASE_IMAGE}" --build-arg "DEBIAN_SNAPSHOT=${TOOLCHAIN_DEBIAN_SNAPSHOT}" \
  --tag "${image}" "${repo_dir}/toolchain"
mkdir -p "${evidence_dir}"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "${repo_dir}:/work" \
  --workdir /work/toolchain \
  --env SOURCE_DATE_EPOCH=0 \
  "${image}" make clean all check repro
docker image inspect --format 'id={{.Id}} repo_digests={{json .RepoDigests}}' "${image}" \
  > "${evidence_dir}/container-image.txt"
cp "${repo_dir}/toolchain/build/tool-versions.txt" \
   "${repo_dir}/toolchain/build/artifacts.sha256" \
   "${evidence_dir}/"
