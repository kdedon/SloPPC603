#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
# Frees runner disk for the Quartus image by removing preinstalled SDKs the
# builds never use.
set -euo pipefail
df -h /
sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /usr/local/.ghcup \
  /opt/hostedtoolcache/CodeQL /usr/local/share/boost /usr/share/swift
sudo docker image prune --all --force > /dev/null
df -h /
