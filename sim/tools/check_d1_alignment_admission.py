#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Optional bounded four-state D1 admission proof, not a temporal CPU proof."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import tempfile
from d1_admission_proof import admission, composition, source

FIXTURES = (
    ('tb_d1_admission', admission.fixture,
     '618cc3c52672d00e3b4ad8ad4b56be233806ee1dcedea69dbadce3cc1db7a820',
     ('PASS D1 bounded admission samples=851968 priority=262144',
      'PASS targeted semantic counterexamples=3')),
    ('tb_d1_composition', composition.fixture,
     'a80ba69376cf43db1bc5029ba4d8a44d542e62fa782a8c06736128f85bb27c6a',
     ('PASS actual D1 composition samples=196608',)),
)


def bounded(command, seconds, log):
    """One process group at a time; clean up even after interruption/timeout."""
    print('RUN', ' '.join(map(str, command)), flush=True)
    with log.open('w') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            status = process.wait(timeout=seconds)
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
    text = log.read_text()
    print(text, end='', flush=True)
    if status:
        raise RuntimeError(f'phase exit {status}: {log}')
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    old, new, package = source.load(args.root)
    negatives = source.negative_guards(new, package)
    print(f'SOURCE PASS actual_core={source.sha((args.root / "rtl/ppc_core.sv").read_text())} '
          f'D1_view={source.sha(new)} inverse={source.sha(old)} '
          f'package={source.sha(package)} source-negative-guards={negatives}', flush=True)
    args.output.mkdir(parents=True, exist_ok=True)
    prepared = []
    for top, generator, expected, certificates in FIXTURES:
        text = generator(old, new, package)
        assert source.sha(text) == expected, ('fixture drift', top)
        path = args.output / (top + '.sv')
        path.write_text(text)
        prepared.append((top, path, certificates))
        print(f'FIXTURE {top} sha256={expected}', flush=True)
    if args.prepare_only:
        print('PREPARED ONLY: no HDL execution', flush=True)
        return
    # Two fixtures execute serially. The owned temporary directory removes all
    # VVP products on success, failure, interruption or phase timeout.
    with tempfile.TemporaryDirectory(prefix='d1-vvp-', dir=args.output) as scratch:
        for top, path, certificates in prepared:
            product = Path(scratch) / (top + '.vvp')
            bounded(['iverilog', '-g2012', '-s', top, '-o', str(product), str(path)],
                    30, args.output / (top + '-compile.log'))
            output = bounded(['vvp', str(product)], 120, args.output / (top + '-run.log'))
            for certificate in certificates:
                assert certificate in output, ('missing runtime certificate', certificate)
    # Re-read actual sources after both phases; no silent mid-run source change.
    assert source.load(args.root) == (old, new, package), 'source changed during proof'
    print('PASS D1 source-connected bounded proof: admission=851968 composition=196608 '
          'behavioral-counterchecks=3 source-negative-guards=9; temporal/physical proof excluded',
          flush=True)


if __name__ == '__main__':
    main()
