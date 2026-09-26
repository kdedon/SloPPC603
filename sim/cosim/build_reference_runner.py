#!/usr/bin/env python3
"""Build the flat-RAM reference runner once for several comparison runs."""
import argparse
from pathlib import Path
import subprocess
import sys
from reference_checkout import add_arguments, verify
from run_reference import PROJECT, ROOT, build_reference


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=PROJECT/'sim/build/reference-runner-flat')
    add_arguments(parser)
    args = parser.parse_args()
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    ref = ROOT/'dingusppc'
    verify(ref, args.allow_unpinned_reference)
    runner, _ = build_reference(build, ref, flat_ram=True)
    print(f'Built {runner}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
