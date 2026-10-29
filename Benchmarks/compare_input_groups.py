#!/usr/bin/env python3
"""Compare package-only extraction policies sequentially with optional cache purging."""
import argparse
import json
import statistics
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('fixtures', type=Path)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--repeats', type=int, default=3)
parser.add_argument('--baseline', required=True, type=Path)
parser.add_argument('--policies', nargs='+', choices=['default', '1', '5', '10', '25'], default=['25', '1', '5', '10'])
parser.add_argument('--purge', action='store_true', help='Forward checked sudo -n purge to each measured case')
args = parser.parse_args()
if args.repeats < 1:
    parser.error('--repeats must be positive')
args.output.mkdir(parents=True, exist_ok=False)
# A read after an initial purge requests source data before measurement, so drive
# wake-up is less likely to fall inside the first case. Every case purges again.
if args.purge:
    purge = subprocess.run(['sudo', '-n', '/usr/sbin/purge'], capture_output=True, text=True)
    (args.output / 'preflight-purge.json').write_text(json.dumps({
        'returncode': purge.returncode, 'stdout': purge.stdout, 'stderr': purge.stderr,
    }, indent=2))
    if purge.returncode:
        raise RuntimeError('Preflight purge failed: authenticate with sudo -v and retry with a new output directory. ' + purge.stderr.strip())
    videos = sorted(args.fixtures.glob('*.mp4'))
    if not videos:
        raise RuntimeError('No MP4 fixtures for drive preflight')
    video = videos[0]
    with video.open('rb') as handle:
        offset = video.stat().st_size // 2
        handle.seek(offset)
        read_bytes = len(handle.read(4096))
    (args.output / 'drive-preflight.json').write_text(json.dumps({
        'file': str(video), 'offset': offset, 'bytes_read': read_bytes,
        'note': 'Source read after preflight purge, before all measured cases; controller caches remain uncontrolled.',
    }, indent=2))
records = []
# Each policy gets equivalent sequential/client-2 cases. Reverse policy order on
# alternate rounds to reduce ordering bias; all runs still use uncontrolled caches.
for repeat in range(args.repeats):
    policies = [None if value == 'default' else int(value) for value in args.policies]
    if repeat % 2:
        policies.reverse()
    for policy in policies:
        name = f'{"default" if policy is None else policy}-r{repeat + 1}'
        folder = args.output / name
        command = ['python3', 'Benchmarks/run.py', str(args.fixtures), '--output', str(folder),
                   '--repeats', '1', '--cases', 'combined-1', 'client-2', '--baseline', str(args.baseline)]
        if policy is not None:
            command += ['--ffmpeg-inputs', str(policy)]
        if args.purge:
            command += ['--purge']
        print(f'Policy {policy if policy is not None else "production default"}, round {repeat + 1}', flush=True)
        subprocess.run(command, check=True)
        for result in json.loads((folder / 'results.json').read_text()):
            result.update(policy=policy, round=repeat + 1)
            records.append(result)
        (args.output / 'results.json').write_text(json.dumps(records, indent=2))

lines = ['# FFmpeg input grouping experiment', '',
         ('Release build. Successful purge required before each case. ' if args.purge else 'Release build. No purge; compare policies within this experiment rather than against the purged baseline. ') + 'Selected policies are run sequentially, with policy order reversed in alternate rounds. Each case hashes the fixture corpus.', '',
         '| Inputs per process | Mode | Median seconds | Runs (seconds) | Median peak tree RSS (MiB) | Max peak tree RSS (MiB) | FFmpeg launch attempts per case |',
         '|---|---|---:|---|---:|---:|---|']
for policy in [None if value == 'default' else int(value) for value in args.policies]:
    for mode in ['combined', 'client']:
        values = [r for r in records if r['policy'] == policy and r['mode'] == mode]
        times = ', '.join(f'{r["seconds"]:.3f}' for r in values)
        memory = [r['peak_tree_rss_kib'] / 1024 for r in values]
        counts = ', '.join(str(r['ffmpegLaunchAttempts']) for r in values)
        label = f'default ({values[0].get("ffmpegInputsPerProcess") or 25})' if policy is None else policy
        lines.append(f'| {label} | {mode} | {statistics.median(r["seconds"] for r in values):.3f} | {times} | {statistics.median(memory):.1f} | {max(memory):.1f} | {counts} |')
lines += ['', 'Every recorded hash matched the accepted baseline. Launch attempts include duration probes; peaks include descendants and may double-count shared pages. Brief peaks may be missed. Input limit 25 explicitly reproduces the original all-input extraction. Default follows the production policy in the built binary.', '']
(args.output / 'REPORT.md').write_text('\n'.join(lines))
