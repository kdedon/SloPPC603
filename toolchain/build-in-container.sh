#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Run make targets in the pinned cross-compiler container, from the repo root.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/ci/pins.env"
exec docker run --rm --network none --user "$(id -u):$(id -g)" \
  --volume "$root:/work" --workdir /work/toolchain \
  "${TOOLCHAIN_IMAGE:-$TOOLCHAIN_IMAGE_PIN}" make "$@"
