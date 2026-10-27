#!/usr/bin/env python3
"""Release benchmark; sample simultaneous RSS of the runner and its descendants."""
import argparse
import json
import platform
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('fixtures', type=Path)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--repeats', type=int, default=3)
parser.add_argument('--ffmpeg-inputs', type=int, help='Package-only extraction input-group experiment')
parser.add_argument('--cases', nargs='+', choices=['combined-1','phash-1','oshash-1','batch-2','client-2','batch-4','client-4'], help='Selected modes; default is the full matrix')
parser.add_argument('--purge', action='store_true', help='Require sudo -n purge before every measured case; authenticate with sudo -v first')
parser.add_argument('--baseline', type=Path, help='Prior results.json whose hashes must remain identical')
args = parser.parse_args()
if args.repeats < 1:
    parser.error('--repeats must be positive')
if args.ffmpeg_inputs is not None and args.ffmpeg_inputs < 1:
    parser.error('--ffmpeg-inputs must be positive')
args.output.mkdir(parents=True, exist_ok=False)
binary = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], text=True).strip()) / 'hash-benchmark'
metadata = {
    'platform': platform.platform(),
    'ffmpeg_inputs_per_process': args.ffmpeg_inputs,
    'selected_cases': args.cases,
    'fixture_directory': str(args.fixtures.resolve()),
    'baseline': str(args.baseline.resolve()) if args.baseline else None,
    'swift': subprocess.check_output(['swift', '--version'], text=True),
    'hardware': subprocess.check_output(['sysctl', 'hw.model', 'hw.memsize', 'hw.ncpu'], text=True),
    'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'ffmpeg': subprocess.check_output(['ffmpeg', '-version'], text=True).splitlines()[0],
    'fixtures': [{'file': p.name, 'bytes': p.stat().st_size, 'mtime_ns': p.stat().st_mtime_ns} for p in sorted(args.fixtures.glob('*.mp4'))],
    'sampling': 'ps RSS KiB, nominal 100ms interval plus ps overhead; summed simultaneous descendants; shared pages may be double counted; brief peaks may be missed',
    'purge_before_each_case': args.purge,
    'cache': ('sudo -n /usr/sbin/purge required before every case, outside timing; device caches and within-case caching remain uncontrolled.' if args.purge else 'No filesystem cache purge. First combined run retained separately; subsequent runs use uncontrolled/warmed OS caches.'),
}
(args.output / 'environment.json').write_text(json.dumps(metadata, indent=2))
expected = {}
if args.baseline:
    for report in json.loads(args.baseline.read_text()):
        for measurement in report['measurements']:
            for key in ('phash', 'oshash'):
                if key in measurement:
                    expected[(measurement['file'], key)] = measurement[key]
records = []
cases = [('combined', 1), ('phash', 1), ('oshash', 1), ('batch', 2), ('client', 2), ('batch', 4), ('client', 4)]
if args.cases:
    cases = [(case.rsplit('-', 1)[0], int(case.rsplit('-', 1)[1])) for case in args.cases]
for repeat in range(args.repeats):
    # Reverse after the first round to reduce fixed-order bias.
    for mode, limit in cases if repeat % 2 == 0 else list(reversed(cases)):
        name = f'{repeat + 1}-{mode}-{limit}'
        output = args.output / f'{name}.json'
        purge_seconds = None
        if args.purge:
            purge_start = time.monotonic()
            purge = subprocess.run(['sudo', '-n', '/usr/sbin/purge'], capture_output=True, text=True)
            purge_seconds = time.monotonic() - purge_start
            (args.output / f'{name}-purge.json').write_text(json.dumps({
                'returncode': purge.returncode, 'seconds': purge_seconds,
                'stdout': purge.stdout, 'stderr': purge.stderr,
            }, indent=2))
            if purge.returncode != 0:
                raise RuntimeError('Cache purge failed; no benchmark launched for this case. Run sudo -v in this terminal before retrying with a new output directory. ' + purge.stderr.strip())
        start = time.monotonic()
        peak_parent = peak_tree = peak_children = samples = 0
        with (args.output / f'{name}.log').open('w') as log:
            process = subprocess.Popen([str(binary), str(args.fixtures.resolve()), mode, str(limit), str(output.resolve())] + ([str(args.ffmpeg_inputs)] if args.ffmpeg_inputs is not None else []), stdout=log, stderr=subprocess.STDOUT)
            while process.poll() is None:
                rows = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss='], text=True)
                table = [tuple(map(int, row.split())) for row in rows.splitlines() if row.strip()]
                pids = {process.pid}
                while True:
                    expanded = pids | {pid for pid, parent, rss in table if parent in pids}
                    if expanded == pids:
                        break
                    pids = expanded
                parent_rss = sum(rss for pid, parent, rss in table if pid == process.pid)
                tree_rss = sum(rss for pid, parent, rss in table if pid in pids)
                peak_parent = max(peak_parent, parent_rss)
                peak_tree = max(peak_tree, tree_rss)
                peak_children = max(peak_children, len(pids) - 1)
                samples += 1
                time.sleep(0.1)
            if process.returncode:
                raise RuntimeError(f'{name} failed; see {log.name}')
        report = json.loads(output.read_text())
        if 'ffmpegInputsPerProcess' in report:
            metadata['ffmpeg_inputs_per_process'] = report['ffmpegInputsPerProcess']
            (args.output / 'environment.json').write_text(json.dumps(metadata, indent=2))
        for measurement in report['measurements']:
            for key in ('phash', 'oshash'):
                if key in measurement:
                    identity = (measurement['file'], key)
                    if identity in expected and expected[identity] != measurement[key]:
                        raise AssertionError(f'Hash mismatch: {identity}, {name}')
                    expected[identity] = measurement[key]
        report.update(purge_succeeded=args.purge, purge_seconds=purge_seconds, repeat=repeat + 1, peak_parent_rss_kib=peak_parent, peak_tree_rss_kib=peak_tree,
                      peak_child_count=peak_children, samples=samples, process_wall_seconds=time.monotonic() - start)
        output.write_text(json.dumps(report, indent=2))
        records.append(report)
        (args.output / 'results.json').write_text(json.dumps(records, indent=2))
        print(f'{name}: {report["seconds"]:.3f}s, parent {peak_parent/1024:.1f} MiB, tree {peak_tree/1024:.1f} MiB; hashes consistent', flush=True)
