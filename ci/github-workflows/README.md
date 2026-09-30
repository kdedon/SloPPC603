<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Draft workflows

Inactive: GitHub runs only `.github/workflows/`. What each workflow does, the
runner limits and the steps to enable them are in [docs/CI.md](../../docs/CI.md#draft-workflows).

| File | Trigger |
| --- | --- |
| `quick.yml` | push, pull request |
| `mister-unstable.yml` | push to `main` |
| `release.yml` | tag `v*` |
