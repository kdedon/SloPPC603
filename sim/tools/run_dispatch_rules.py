#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Run demo SoC programs and check their dispatch traces against the 603e rules.

The model streams +DISPATCH_TRACE into a FIFO read by check_dispatch_trace's
rule checker, so no trace is stored.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from check_dispatch_trace import check_rules, read_image, require


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--image-dir', type=Path, required=True)
    parser.add_argument('--programs', nargs='+', required=True)
    parser.add_argument('--width', type=int, required=True)
    parser.add_argument('--sru', action='store_true')
    parser.add_argument('--min-pairs', type=int, default=0)
    parser.add_argument('--early-move', action='store_true',
                        help='accept a move to LR/CTR feeding a branch before it retires (AUD-90)')
    parser.add_argument('--log-dir', type=Path, required=True)
    args = parser.parse_args()
    args.log_dir.mkdir(parents=True, exist_ok=True)
    try:
        for name in args.programs:
            image = (args.image_dir/f'{name}.hex').resolve()
            words = read_image(image, 0xfff00000)
            with tempfile.TemporaryDirectory(dir=args.log_dir) as scratch:
                fifo = Path(scratch)/'events'
                os.mkfifo(fifo)
                with (args.log_dir/f'{name}.log').open('w') as log:
                    sim = subprocess.Popen([str(args.model), f'+IMAGE={image}', f'+NAME={name}',
                                            f'+DISPATCH_TRACE={fifo}'], stdout=log, stderr=subprocess.STDOUT)
                    try:
                        with fifo.open() as lines:
                            st = check_rules(lines, args.width, words, args.sru, early_move=args.early_move)
                    except ValueError:
                        sim.kill()
                        raise
                    code = sim.wait()
            text = (args.log_dir/f'{name}.log').read_text()
            require(code == 0 and f'PASS {name}' in text, f'{name}: model failed\n{text[-2000:]}')
            require(st['pairs_dispatched'] >= args.min_pairs and st['pairs_retired'] >= args.min_pairs,
                    f'{name}: fewer than {args.min_pairs} dispatched or retired pairs')
            print(f'PASS dispatch rules {name} width {args.width}: ' +
                  ' '.join(f'{k}={v}' for k, v in st.items()), flush=True)
    except ValueError as error:
        sys.exit(f'FAIL dispatch rules: {error}')


if __name__ == '__main__':
    main()
