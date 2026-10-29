# VideoHash baseline — hdd-baseline-2026-10-27

Release build; default configuration; 6 local MP4 fixtures.

Base revision: `2220900f4919a2dd9cf4be64a5754472bb6d4de3`. macOS-27.0.1-arm64-arm-64bit-Mach-O.
Fixtures: `/Volumes/Ext-6TB-2/HashTestVids`.
`ffmpeg version 9.0.2 Copyright (c) 2000-2026 the FFmpeg developers`. Hardware: hw.model: MacBookPro18,3; hw.memsize: 17179869184; hw.ncpu: 8;

## Whole-corpus results

| Mode | Limit | Runs (seconds) | Median (seconds) | Maximum sampled Swift RSS (MiB) | Maximum sampled process-tree RSS (MiB) |
|---|---:|---|---:|---:|---:|
| combined | 1 | 9.556, 9.011, 10.359 | 9.556 | 31.5 | 2488.3 |
| phash | 1 | 9.082, 8.824, 12.543 | 9.082 | 30.2 | 2498.1 |
| oshash | 1 | 0.035, 0.038, 0.074 | 0.038 | 8.0 | 8.0 |
| batch | 2 | 7.771, 7.062, 9.223 | 7.771 | 38.5 | 3319.5 |
| client | 2 | 8.121, 8.766, 8.113 | 8.121 | 40.3 | 3425.0 |
| batch | 4 | 7.123, 7.477, 7.765 | 7.477 | 42.1 | 3952.6 |
| client | 4 | 7.579, 7.253, 7.143 | 7.253 | 43.1 | 3753.8 |

## Hash fingerprints and sequential timing

| File | PHash | OSHash | Duration (s) | First combined run (s) | Median combined run (s) |
|---|---|---|---:|---:|---:|
| V1.mp4 | `e6e2e0e6e2e2e04d` | `8f0b4a25ceaf96c8` | 3310.674 | 2.676 | 2.846 |
| V2.mp4 | `d5e26411f679a2e2` | `d718ecc60e04593a` | 525.000 | 1.012 | 0.995 |
| V3.mp4 | `a03f55c4469dba99` | `1e5c53bdc1ceba12` | 2001.048 | 1.585 | 1.585 |
| V4.mp4 | `d2f868f8e87eb030` | `686064db3eafb762` | 3421.618 | 1.924 | 1.924 |
| V5.mp4 | `8c98873d8e3e636a` | `bd3ed665e2f76e1f` | 2795.760 | 1.217 | 1.155 |
| V6.mp4 | `b724a198db7ac4cc` | `9141445d9de673a2` | 3017.533 | 1.142 | 1.002 |

## Interpretation and limits

The files had just been copied to this drive. A follow-up physical-disk sample showed very little I/O, so these results largely reflect filesystem caching, not uncached HDD seek performance. See [the comparison](../COMPARISON.md). Full-file SHA-256 verification after timing confirmed all six copies match the SSD originals.

- Every hash matched across modes and repeats; this is implementation consistency, not an independent reference certification.
- First combined run is an initial observed pass, not a controlled cold-cache run. No cache purge or warm-up exclusion. Subsequent measurements benefit from caches.
- RSS sampled approximately every 100 ms plus sampler overhead. Tree RSS includes descendants and may double-count shared pages; it is not physical footprint and can miss brief peaks.
- OSHash runs are too short for meaningful sampled peak memory; use their elapsed times only as coarse measurements.
- Background contention and thermal/power conditions were not controlled. These results are a local working baseline, not an isolated benchmark.
- All cases use fresh processes and one shared generator within each case. Client mode uses a bounded task group calling the single-video API; batch mode uses the library batch API.
- 20 existing Swift Testing tests passed in release configuration. No library algorithms were modified.

Raw runs: `results.json`; environment and fixture sizes/mtimes: `environment.json`; full fixture identities: `fixtures.json`.
