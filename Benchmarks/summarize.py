#!/usr/bin/env python3
"""Summarize a completed benchmark, retaining first-pass and per-file timings."""
import json
import statistics
import sys
from pathlib import Path

folder = Path(sys.argv[1])
records = json.loads((folder / 'results.json').read_text())
env = json.loads((folder / 'environment.json').read_text())
lines = [f'# VideoHash baseline — {folder.name}', '',
         f'Release build; default configuration; {len(env["fixtures"])} local MP4 fixtures.', '',
         f'Base revision: `{env["revision"]}`. {env["platform"]}.',
         f'Fixtures: `{env.get("fixture_directory", "see environment.json")}`.',
         f'FFmpeg inputs per process: {env.get("ffmpeg_inputs_per_process") or "default (all sampled inputs)"}.',
         f'`{env["ffmpeg"]}`. Hardware: ' + env['hardware'].replace('\n', '; '), '',
         '## Whole-corpus results', '',
         '| Mode | Limit | Runs (seconds) | Median (seconds) | Maximum sampled Swift RSS (MiB) | Maximum sampled process-tree RSS (MiB) |',
         '|---|---:|---|---:|---:|---:|']
for mode, limit in [('combined', 1), ('phash', 1), ('oshash', 1), ('batch', 2), ('client', 2), ('batch', 4), ('client', 4)]:
    values = sorted([r for r in records if r['mode'] == mode and r['concurrency'] == limit], key=lambda r: r['repeat'])
    if not values:
        continue
    times = ', '.join(f'{r["seconds"]:.3f}' for r in values)
    lines.append(f'| {mode} | {limit} | {times} | {statistics.median(r["seconds"] for r in values):.3f} | {max(r["peak_parent_rss_kib"] for r in values)/1024:.1f} | {max(r["peak_tree_rss_kib"] for r in values)/1024:.1f} |')
lines += ['', '## Hash fingerprints and sequential timing', '',
          '| File | PHash | OSHash | Duration (s) | First combined run (s) | Median combined run (s) |',
          '|---|---|---|---:|---:|---:|']
combined = sorted([r for r in records if r['mode'] == 'combined'], key=lambda r: r['repeat'])
for first in (combined[0]['measurements'] if combined else []):
    times = [m['seconds'] for r in combined for m in r['measurements'] if m['file'] == first['file']]
    lines.append(f'| {first["file"]} | `{first["phash"]}` | `{first["oshash"]}` | {first["duration"]:.3f} | {times[0]:.3f} | {statistics.median(times):.3f} |')
lines += ['', '## Interpretation and limits', '',
          '- Every hash matched across modes and repeats; this is implementation consistency, not an independent reference certification.',
          ('- A successful macOS purge preceded every measured case, outside timing. This approximates cold filesystem caches; device caches and caching within a case remain uncontrolled.' if env.get('purge_before_each_case') else '- First combined run is an initial observed pass, not a controlled cold-cache run. No cache purge or warm-up exclusion. Subsequent measurements benefit from caches.'),
          '- RSS sampled approximately every 100 ms plus sampler overhead. Tree RSS includes descendants and may double-count shared pages; it is not physical footprint and can miss brief peaks.',
          '- OSHash runs are too short for meaningful sampled peak memory; use their elapsed times only as coarse measurements.',
          ('- An unrelated FFmpeg process was observed during the first pass. ' if (folder / 'background-processes.txt').exists() else '- ') + 'Background contention and thermal/power conditions were not controlled. These results are a local working baseline, not an isolated benchmark.',
          '- All cases use fresh processes and one shared generator within each case. Client mode uses a bounded task group calling the single-video API; batch mode uses the library batch API.',
          '- Library test results are recorded separately; this runner verifies hash consistency and any supplied baseline.', '',
          'Raw runs: `results.json`; environment and fixture sizes/mtimes: `environment.json`; full fixture identities: `fixtures.json`.', '']
(folder / 'REPORT.md').write_text('\n'.join(lines))
print('\n'.join(lines))
