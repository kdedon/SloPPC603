#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Apply bounded host flags only to named, opt-in frontend acceptance tops."""
import json
import os
from pathlib import Path
import sys

ALLOWED_TOPS = {
    "tb_core_bat_cached_bus60x", "tb_core_bat_cached_bus60x_drain",
    "tb_core_bat_cached_bus60x_coherence", "tb_core_bat_cached_bus60x_irq",
    "tb_core_bat_cached_bus60x_cacheops", "tb_core_bat_cached_bus60x_stress",
    "tb_core_bat_cached_bus60x_timer", "tb_chip_firmware",
    "tb_chip_icache_real", "tb_chip_pins",
}


def main():
    real = Path(__file__).resolve().with_name("verilate")
    args = sys.argv[1:]
    if args == ["--version"]:
        os.execv(str(real), [str(real), *args])
    value = os.environ.get("PPC_FETCH_HINTS_VALUE", "1")
    if value not in ("0", "1"):
        raise SystemExit("PPC_FETCH_HINTS_VALUE must be 0 or 1")
    if args.count("--top-module") != 1:
        raise SystemExit("fetch-hint compiler requires one explicit --top-module")
    index = args.index("--top-module")
    if index + 1 >= len(args) or args[index + 1] not in ALLOWED_TOPS:
        raise SystemExit("top does not expose the guarded ENABLE_FETCH_HINTS parameter")
    filtered = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ("-j", "--build-jobs", "-MAKEFLAGS"):
            if i + 1 >= len(args):
                raise SystemExit("missing compiler option value")
            i += 2
            continue
        if ((arg.startswith("-j") and arg[2:].isdigit()) or
                arg.startswith("--build-jobs=")):
            i += 1
            continue
        if arg.startswith("-GENABLE_FETCH_HINTS="):
            raise SystemExit("select hint mode through the runner, not duplicate -G overrides")
        filtered.append(arg)
        i += 1
    command = [str(real), *filtered, "-j", "1", "-MAKEFLAGS",
               "OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0",
               "-GENABLE_FETCH_HINTS=1'b" + value, "+define+PPC_LSU_PIPE=1"]
    log = os.environ.get("PPC_FETCH_HINTS_ARGV_LOG")
    if log:
        with Path(log).open("a") as stream:
            stream.write(json.dumps({"cwd": os.getcwd(), "argv": command,
                                    "PPC_VERILATOR_FLAGS": os.environ.get("PPC_VERILATOR_FLAGS", "")}) + "\n")
    environment = dict(os.environ, OBJCACHE="")
    # Preserve the canonical wrapper's final -fno-const-bit-op-tree and cleanup.
    os.execve(str(real), command, environment)


if __name__ == "__main__":
    main()
