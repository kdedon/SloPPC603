# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
from pathlib import Path
import runpy

def fixture(o, n, p):
    return runpy.run_path(str(Path(__file__).with_name("composition_engine.py")), init_globals={'o': o, 'n': n, 'p': p})['code']
