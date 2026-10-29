# VideoHash baseline — baseline-2026-10-27

Release build; default configuration; 6 local MP4 fixtures.

Base revision: `2220900f4919a2dd9cf4be64a5754472bb6d4de3`. macOS-27.0.1-arm64-arm-64bit-Mach-O.
Fixtures: `/Users/francois/Dev/HashTestVids`.
`ffmpeg version 9.0.2 Copyright (c) 2000-2026 the FFmpeg developers`. Hardware: hw.model: MacBookPro18,3; hw.memsize: 17179869184; hw.ncpu: 8;

## Whole-corpus results

| Mode | Limit | Runs (seconds) | Median (seconds) | Maximum sampled Swift RSS (MiB) | Maximum sampled process-tree RSS (MiB) |
|---|---:|---|---:|---:|---:|
| combined | 1 | 28.481, 9.344, 9.302 | 9.344 | 32.4 | 2518.8 |
| phash | 1 | 9.685, 9.734, 11.685 | 9.734 | 32.7 | 2512.4 |
| oshash | 1 | 0.045, 0.038, 0.064 | 0.045 | 8.7 | 8.7 |
| batch | 2 | 8.233, 9.278, 10.414 | 9.278 | 38.1 | 3403.9 |
| client | 2 | 8.101, 7.699, 8.990 | 8.101 | 39.4 | 4117.2 |
| batch | 4 | 7.377, 7.502, 7.570 | 7.502 | 43.3 | 3993.5 |
| client | 4 | 7.081, 7.039, 7.136 | 7.081 | 46.4 | 3725.7 |

## Hash fingerprints and sequential timing

| File | PHash | OSHash | Duration (s) | First combined run (s) | Median combined run (s) |
|---|---|---|---:|---:|---:|
| V1.mp4 | `e6e2e0e6e2e2e04d` | `8f0b4a25ceaf96c8` | 3310.674 | 11.878 | 2.584 |
| V2.mp4 | `d5e26411f679a2e2` | `d718ecc60e04593a` | 525.000 | 2.386 | 1.009 |
| V3.mp4 | `a03f55c4469dba99` | `1e5c53bdc1ceba12` | 2001.048 | 4.114 | 1.862 |
| V4.mp4 | `d2f868f8e87eb030` | `686064db3eafb762` | 3421.618 | 7.779 | 2.088 |
| V5.mp4 | `8c98873d8e3e636a` | `bd3ed665e2f76e1f` | 2795.760 | 1.234 | 1.080 |
| V6.mp4 | `b724a198db7ac4cc` | `9141445d9de673a2` | 3017.533 | 1.089 | 0.968 |

## Interpretation and limits

- Every hash matched across modes and repeats; this is implementation consistency, not an independent reference certification.
- First combined run is an initial observed pass, not a controlled cold-cache run. No cache purge or warm-up exclusion. Subsequent measurements benefit from caches.
- RSS sampled approximately every 100 ms plus sampler overhead. Tree RSS includes descendants and may double-count shared pages; it is not physical footprint and can miss brief peaks.
- OSHash runs are too short for meaningful sampled peak memory; use their elapsed times only as coarse measurements.
- An unrelated FFmpeg process was observed during the first pass. Background contention and thermal/power conditions were not controlled. These results are a local working baseline, not an isolated benchmark.
- All cases use fresh processes and one shared generator within each case. Client mode uses a bounded task group calling the single-video API; batch mode uses the library batch API.
- 20 existing Swift Testing tests passed in release configuration. No library algorithms were modified.

Raw runs: `results.json`; environment and fixture sizes/mtimes: `environment.json`; full fixture identities: `fixtures.json`.
