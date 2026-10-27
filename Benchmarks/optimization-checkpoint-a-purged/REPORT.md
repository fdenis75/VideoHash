# Purged HDD checkpoint A comparison

All 21 cases completed; all 21 purge records report success; every PHash and OSHash was independently compared with the accepted baseline and matched. No warnings/errors were found in the run logs.

## Elapsed time

| Mode | Videos at once | Baseline runs (s) | Checkpoint runs (s) | Baseline median (s) | Checkpoint median (s) | Median change |
|---|---:|---|---|---:|---:|---:|
| combined | 1 | 9.882, 9.679, 9.827 | 9.589, 9.184, 9.465 | 9.827 | 9.465 | -3.7% |
| phash | 1 | 9.386, 9.873, 11.275 | 9.391, 9.409, 9.176 | 9.873 | 9.391 | -4.9% |
| oshash | 1 | 0.254, 0.250, 0.249 | 0.252, 0.256, 0.236 | 0.250 | 0.252 | +1.0% |
| batch | 2 | 7.603, 9.082, 8.262 | 7.891, 7.737, 8.133 | 8.262 | 7.891 | -4.5% |
| client | 2 | 7.794, 7.862, 8.300 | 7.715, 7.588, 7.973 | 7.862 | 7.715 | -1.9% |
| batch | 4 | 9.901, 7.628, 11.605 | 7.526, 7.021, 7.594 | 9.901 | 7.526 | -24.0% |
| client | 4 | 8.994, 7.585, 11.310 | 9.362, 9.637, 8.584 | 8.994 | 9.362 | +4.1% |

## Sampled process-tree memory

RSS includes FFmpeg descendants, may double-count shared pages, and can miss short peaks. These figures are not physical footprint.

| Mode | Videos at once | Baseline median peak (MiB) | Checkpoint median peak (MiB) | Baseline maximum (MiB) | Checkpoint maximum (MiB) |
|---|---:|---:|---:|---:|---:|
| combined | 1 | 2444.9 | 2309.7 | 2545.2 | 2368.6 |
| batch | 2 | 3175.5 | 3519.1 | 3395.8 | 4034.0 |
| client | 2 | 3047.1 | 3769.4 | 3323.6 | 4102.4 |
| batch | 4 | 3303.9 | 3904.2 | 3907.5 | 4237.4 |
| client | 4 | 3480.0 | 4188.5 | 3698.8 | 4758.6 |

## Drive spin-up observation

The user heard the drive wake/spin up during this checkpoint, unlike the accepted baseline. The timing of that event was not recorded. Retain every sample; do not selectively remove the first run.

The first combined run took 9.589 s versus 9.184 s and 9.465 s subsequently. Its first file took 2.851 s versus 2.698 s and 2.668 s. There is no large first-case outlier. Wake-up could have happened during the pre-measurement fixture directory/stat collection, or within a measured operation; the logs do not establish which. Purge duration is excluded from timing, including a 5.448 s purge before third-round PHash. Do not attribute that delay to spin-up without evidence.

For future comparisons, wake the drive before the matrix, then purge before each measured case as usual. This separates drive readiness from filesystem-cache effects without dropping observations. It does not guarantee cold controller caches.

## Assessment

- Correctness and lifecycle milestone validated; no hash changes.
- Most timing changes are small compared with the limited sample size and uncontrolled system conditions. Batch concurrency four improved substantially in this run, but client concurrency four did not. Do not claim a uniform throughput improvement.
- Concurrent process-tree memory increased in median as well as maximum samples. This is an observed regression to investigate, not a demonstrated leak. Less blocking may permit decoder work to overlap differently, but these measurements do not prove the cause.
- The Swift parent stayed below 37 MiB in this checkpoint. FFmpeg and concurrent decode activity remain the main memory target.
- Concurrency two remains the sensible starting point for client-managed work on this fixture set. Do not increase it merely because one batch case improved.
- Keep the correctness fixes, but carry the higher concurrent-memory measurements into the next resource-control experiment. Smaller Swift buffers alone will not explain or eliminate multi-GiB decoder usage.

Baseline: `../hdd-purged-2026-10-27/results.json`. Candidate: `results.json`. No source changes were made while analyzing this checkpoint.
