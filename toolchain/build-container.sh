#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image="${TOOLCHAIN_IMAGE:-ppc603e-cross:bookworm-20250811}"
evidence_dir="${repo_dir}/toolchain/evidence"

docker build --pull=false --provenance=false --build-arg SOURCE_DATE_EPOCH=0 \
  --tag "${image}" "${repo_dir}/toolchain"
mkdir -p "${evidence_dir}"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  --volume "${repo_dir}:/work" \
  --workdir /work/toolchain \
  --env SOURCE_DATE_EPOCH=0 \
  "${image}" make clean all check repro
docker image inspect --format 'id={{.Id}} repo_digests={{join .RepoDigests ","}}' "${image}" \
  > "${evidence_dir}/container-image.txt"
cp "${repo_dir}/toolchain/build/tool-versions.txt" \
   "${repo_dir}/toolchain/build/artifacts.sha256" \
   "${evidence_dir}/"
