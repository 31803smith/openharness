#!/usr/bin/env python3
"""Run the disposable native fixture and require complete, successful results."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from isolation import conflicting_previews, validate_benchmark_bundle


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--terminals', type=int, choices=(16, 48), default=16)
parser.add_argument('--samples', type=int, default=120)
args = parser.parse_args()
app = args.app.resolve()
output = args.output.resolve()
temporary = Path('/private/tmp').resolve()
if not app.is_relative_to(temporary) or not output.is_relative_to(temporary):
    parser.error('The benchmark app and output must be under /private/tmp')
if not 1 <= args.samples <= 500:
    parser.error('Use between 1 and 500 samples per operation/load')
try:
    validate_benchmark_bundle(app)
except (OSError, ValueError) as error:
    parser.error(str(error))
log = output.with_suffix('.log')
if output.exists() or log.exists():
    parser.error('Choose fresh result and log paths')
processes = subprocess.check_output(['ps', '-axo', 'comm='], text=True)
try:
    conflicts = conflicting_previews(processes)
except ValueError as error:
    parser.error(str(error))
if conflicts:
    parser.error(f'Normally close {", ".join(conflicts)} before measuring; this runner never quits other apps')
output.parent.mkdir(parents=True, exist_ok=True)
command = [
    'open', '-n', '-W', '-o', str(log), '--stderr', str(log),
    '--env', 'FLUTTER_TEST=1',
    '--env', 'HARNESS_NATIVE_BENCHMARK=1',
    '--env', f'HARNESS_BENCH_TERMINALS={args.terminals}',
    '--env', f'HARNESS_BENCH_SAMPLES={args.samples}',
    '--env', f'HARNESS_BENCH_OUTPUT={output}',
    str(app),
]
print(f'Native benchmark: {args.terminals} terminals, {args.samples} samples per group', flush=True)
print('Keep the benchmark foreground. It stops if another app takes focus.', flush=True)
try:
    # Launch Services gives the fixture normal app activation. Executing the
    # bundle binary directly does not reliably activate a native macOS window.
    subprocess.run(command, check=True, timeout=300)
except (subprocess.SubprocessError, OSError) as error:
    sys.exit(f'Benchmark launch/wait failed: {error}. Inspect {log}; close any remaining fixture normally.')
if not output.exists():
    sys.exit(f'No result file was written; inspect {log}')
data = json.loads(output.read_text())
if data.get('success') is not True:
    sys.exit(f'Benchmark failed: {data.get("error")}; details in {output}')
if data.get('terminals') != args.terminals or len(data.get('summaries', [])) != 6:
    sys.exit(f'Incomplete workload in {output}')
for group in data['summaries']:
    timing = group['eventToRaster']
    if timing['samples'] != args.samples:
        sys.exit(f'Incomplete sample count in {output}')
    print(f'{group["load"]:22} {group["operation"]:7} '
          f'p50 {timing["p50Ms"]:7.3f} ms  p95 {timing["p95Ms"]:7.3f} ms  '
          f'p99 {timing["p99Ms"]:7.3f} ms  max {timing["maxMs"]:7.3f} ms')
print(f'Raw samples: {output}')
