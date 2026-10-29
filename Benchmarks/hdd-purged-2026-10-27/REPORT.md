# VideoHash baseline — hdd-purged-2026-10-27

Release build; default configuration; 6 local MP4 fixtures.

Base revision: `2220900f4919a2dd9cf4be64a5754472bb6d4de3`. macOS-27.0.1-arm64-arm-64bit-Mach-O.
Fixtures: `/Volumes/Ext-6TB-2/HashTestVids`.
`ffmpeg version 9.0.2 Copyright (c) 2000-2026 the FFmpeg developers`. Hardware: hw.model: MacBookPro18,3; hw.memsize: 17179869184; hw.ncpu: 8;

## Whole-corpus results

| Mode | Limit | Runs (seconds) | Median (seconds) | Maximum sampled Swift RSS (MiB) | Maximum sampled process-tree RSS (MiB) |
|---|---:|---|---:|---:|---:|
| combined | 1 | 9.882, 9.679, 9.827 | 9.827 | 28.0 | 2545.2 |
| phash | 1 | 9.386, 9.873, 11.275 | 9.873 | 27.9 | 2229.5 |
| oshash | 1 | 0.254, 0.250, 0.249 | 0.250 | 8.7 | 8.7 |
| batch | 2 | 7.603, 9.082, 8.262 | 8.262 | 32.9 | 3395.8 |
| client | 2 | 7.794, 7.862, 8.300 | 7.862 | 35.5 | 3323.6 |
| batch | 4 | 9.901, 7.628, 11.605 | 9.901 | 34.4 | 3907.5 |
| client | 4 | 8.994, 7.585, 11.310 | 8.994 | 32.4 | 3698.8 |

## Hash fingerprints and sequential timing

| File | PHash | OSHash | Duration (s) | First combined run (s) | Median combined run (s) |
|---|---|---|---:|---:|---:|
| V1.mp4 | `e6e2e0e6e2e2e04d` | `8f0b4a25ceaf96c8` | 3310.674 | 3.021 | 3.021 |
| V2.mp4 | `d5e26411f679a2e2` | `d718ecc60e04593a` | 525.000 | 1.069 | 1.079 |
| V3.mp4 | `a03f55c4469dba99` | `1e5c53bdc1ceba12` | 2001.048 | 1.681 | 1.665 |
| V4.mp4 | `d2f868f8e87eb030` | `686064db3eafb762` | 3421.618 | 1.955 | 1.955 |
| V5.mp4 | `8c98873d8e3e636a` | `bd3ed665e2f76e1f` | 2795.760 | 1.065 | 1.085 |
| V6.mp4 | `b724a198db7ac4cc` | `9141445d9de673a2` | 3017.533 | 1.090 | 1.090 |

## Interpretation and limits

- Every hash matched across modes and repeats; this is implementation consistency, not an independent reference certification.
- A successful macOS purge preceded every measured case, outside timing. This approximates cold filesystem caches; device caches and caching within a case remain uncontrolled.
- RSS sampled approximately every 100 ms plus sampler overhead. Tree RSS includes descendants and may double-count shared pages; it is not physical footprint and can miss brief peaks.
- OSHash runs are too short for meaningful sampled peak memory; use their elapsed times only as coarse measurements.
- Background contention and thermal/power conditions were not controlled. These results are a local working baseline, not an isolated benchmark.
- All cases use fresh processes and one shared generator within each case. Client mode uses a bounded task group calling the single-video API; batch mode uses the library batch API.
- 20 existing Swift Testing tests passed in release configuration. No library algorithms were modified.

Raw runs: `results.json`; environment and fixture sizes/mtimes: `environment.json`; full fixture identities from the previously verified HDD copies: `../hdd-baseline-2026-10-27/fixtures.json`.

## Purged-run assessment

All 21 recorded purges returned success, and all hashes independently rechecked against the SSD baseline match. Median client-managed times were 7.862 s at concurrency two and 8.994 s at concurrency four; the library batch medians were 8.262 s and 9.901 s respectively. On this small sample, increasing concurrency to four did not improve median throughput. Sequential combined median was 9.827 s. OSHash-only median rose to 0.250 s from 0.038 s in the cached HDD run.

Treat this as a purge-before-case baseline, not proof that all reads reached the physical disk. No per-case physical I/O measurements were collected, and controller caches and within-case reuse remain uncontrolled.
