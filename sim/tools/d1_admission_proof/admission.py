# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
from pathlib import Path
import runpy

def fixture(old, new, pkg):
    return runpy.run_path(str(Path(__file__).with_name("admission_engine.py")), init_globals={'old': old, 'new': new, 'pkg': pkg})['body']
