# SSD and mechanical-drive baseline comparison

Six videos, three rounds per drive, release build, default hashing configuration. All 42 scenario runs completed with matching hashes. The 20 existing unit tests passed. No hashing implementation changed. Full-file SHA-256 verification after timing confirmed all six HDD copies are byte-for-byte identical to the SSD fixtures.

| Mode | Concurrent videos | SSD median (s) | HDD median (s) | SSD max sampled tree RSS (MiB) | HDD max sampled tree RSS (MiB) |
|---|---:|---:|---:|---:|---:|
| combined | 1 | 9.344 | 9.556 | 2518.8 | 2488.3 |
| phash | 1 | 9.734 | 9.082 | 2512.4 | 2498.1 |
| oshash | 1 | 0.045 | 0.038 | 8.7 | 8.0 |
| batch | 2 | 9.278 | 7.771 | 3403.9 | 3319.5 |
| client | 2 | 8.101 | 8.121 | 4117.2 | 3425.0 |
| batch | 4 | 7.502 | 7.477 | 3993.5 | 3952.6 |
| client | 4 | 7.081 | 7.253 | 3725.7 | 3753.8 |

## What this establishes

- Repeatable hash fingerprints, release timings, and approximate process-tree memory for both source locations.
- FFmpeg dominates sampled memory: the parent Swift process remains below 47 MiB, while the process tree reaches about 4 GiB.
- On these cached runs, four concurrent jobs provide only modest improvement over two and consume more resources than sequential work. This does not establish the best concurrency for uncached HDD access.

## Cache and measurement limitations

- The SSD initial combined pass took 28.481 s; later sequential passes took 9.344 s and 9.302 s. An unrelated FFmpeg process was also observed during the initial pass, so the difference cannot be attributed solely to caching.
- The HDD initial combined pass took 9.556 s. The fixtures had just been copied. A 14-second follow-up disk sample showed only small transfers on physical disk6 (exclude the first iostat row, which reports uptime totals). This strongly suggests the hashing reads were mostly served from filesystem cache.
- Therefore these HDD timings are cached-workload measurements, not a measurement of raw mechanical-drive speed or uncached seeking. Do not conclude that the HDD is as fast as the SSD.
- No cache purge, power-state control, or background-workload isolation was performed. Sampled RSS can double-count shared pages and miss short peaks; OSHash-only jobs are too brief for reliable memory sampling.
- For an uncached HDD follow-up, run before copying/opening the fixtures after a reboot. To compare concurrency limits fairly, each needs equivalent cache conditions; the current full matrix warms later cases. Record physical disk activity throughout each run.
- Temporary BMPs and diagnostic logs remain in the system temporary directory; only source video storage changed. This matches the current library behavior.

## Artifacts

- [SSD detailed report](baseline-2026-10-27/REPORT.md)
  - [HDD detailed report](hdd-baseline-2026-10-27/REPORT.md)
- [Runner instructions](README.md)
- [HDD disk activity](hdd-baseline-2026-10-27/disk-activity.txt)
