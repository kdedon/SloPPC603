"""Reviewed DingusPPC checkout and tool options shared by every reference runner."""
from pathlib import Path
import subprocess
import sys

# The reviewed reference commit; results from any other tree are not comparable.
PINNED_COMMIT = 'cf951f690013cc9466c398d0428d4df50b6ede45'


def add_arguments(parser, prebuilt_runner=False):
    parser.add_argument('--allow-unpinned-reference', action='store_true',
                        help=f'accept a reference checkout other than clean {PINNED_COMMIT[:12]}')
    parser.add_argument('--verilator', default='verilator', help='Verilator executable')
    if prebuilt_runner:
        parser.add_argument('--reference-runner-dir', type=Path,
                            help='reuse the flat-RAM runner from build_reference_runner.py')


def verify(ref, allow_unpinned):
    """Return (HEAD, dirty paths); fail unless ref is the clean pinned commit."""
    if not (ref/'cpu/ppc/ppcopcodes.cpp').is_file():
        raise RuntimeError(f'DingusPPC checkout not found at {ref}; clone it next to this repository '
                           f'and check out {PINNED_COMMIT}')
    head = subprocess.check_output(['git', '-C', str(ref), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = subprocess.check_output(['git', '-C', str(ref), 'status', '--porcelain'], text=True).splitlines()
    if head != PINNED_COMMIT or dirty:
        problem = (f'{ref} is at {head}{" with uncommitted changes" if dirty else ""}; '
                   f'expected clean {PINNED_COMMIT}')
        if not allow_unpinned:
            raise RuntimeError(f'{problem} (--allow-unpinned-reference overrides)')
        print(f'WARNING: {problem}; results are not comparable to recorded evidence', file=sys.stderr)
    return head, dirty
