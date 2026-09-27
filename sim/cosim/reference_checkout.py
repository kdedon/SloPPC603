"""DingusPPC checkout checks and tool options shared by every reference runner."""
from pathlib import Path
import subprocess
import sys

# Runs track the latest DingusPPC. This is the last commit a full reference run
# passed on; when HEAD differs, its log since then explains new mismatches.
LAST_VERIFIED = 'cf951f690013cc9466c398d0428d4df50b6ede45'


def positive_seed(value):
    seed = int(value)
    if seed < 1:
        raise ValueError('seed must be positive')
    return seed


def xrand_build_flags(seed):
    """Verilator flags that randomize uninitialized state; none when seed is None."""
    return [] if seed is None else ['--x-assign', 'unique', '--x-initial', 'unique']


def xrand_run_args(seed):
    return [] if seed is None else [f'+verilator+seed+{seed}', '+verilator+rand+reset+2']


def add_arguments(parser, prebuilt_runner=False):
    parser.add_argument('--verilator', default='verilator', help='Verilator executable')
    parser.add_argument('--xrand-seed', type=positive_seed,
                        help='build the RTL with randomized X state and run it with this seed')
    if prebuilt_runner:
        parser.add_argument('--reference-runner-dir', type=Path,
                            help='reuse the flat-RAM runner from build_reference_runner.py')


def verify(ref):
    """Return (HEAD, dirty paths) and report how the checkout relates to LAST_VERIFIED."""
    if not (ref/'cpu/ppc/ppcopcodes.cpp').is_file():
        raise RuntimeError(f'DingusPPC checkout not found at {ref}; clone it next to this repository')
    head = subprocess.check_output(['git', '-C', str(ref), 'rev-parse', 'HEAD'], text=True).strip()
    dirty = subprocess.check_output(['git', '-C', str(ref), 'status', '--porcelain'], text=True).splitlines()
    print(f'DingusPPC {head[:12]}{" (uncommitted changes)" if dirty else ""}')
    if head != LAST_VERIFIED:
        print(f'DingusPPC {head[:12]} differs from last verified {LAST_VERIFIED[:12]}; on a mismatch, '
              f'review: git -C {ref} log --oneline {LAST_VERIFIED[:12]}..{head[:12]}', file=sys.stderr)
    return head, dirty
