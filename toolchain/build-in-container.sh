#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
# Run make targets in the pinned cross-compiler container, from the repo root.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
exec docker run --rm --network none --user "$(id -u):$(id -g)" \
  --volume "$root:/work" --workdir /work/toolchain \
  ppc603e-cross:bookworm-20250811 make "$@"
