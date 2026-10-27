# FFmpeg input grouping experiment

Release build. No purge; compare policies within this experiment rather than against the purged baseline. Three candidate policies and the unchanged default are run sequentially, with policy order reversed in alternate rounds. Each case hashes the fixture corpus.

| Inputs per process | Mode | Median seconds | Runs (seconds) | Median peak tree RSS (MiB) | Max peak tree RSS (MiB) | FFmpeg launch attempts per case |
|---|---|---:|---|---:|---:|---|
| default (25) | combined | 10.722 | 12.603, 10.722, 10.484 | 1693.1 | 2026.2 | 12, 12, 12 |
| default (25) | client | 10.261 | 10.497, 9.025, 10.261 | 2280.1 | 2391.1 | 12, 12, 12 |
| 1 | combined | 19.873 | 19.467, 19.964, 19.873 | 143.3 | 145.3 | 156, 156, 156 |
| 1 | client | 12.456 | 12.456, 11.660, 16.890 | 235.8 | 240.6 | 156, 156, 156 |
| 5 | combined | 11.383 | 11.266, 13.979, 11.383 | 560.3 | 563.0 | 36, 36, 36 |
| 5 | client | 8.226 | 8.133, 11.021, 8.226 | 908.9 | 916.0 | 36, 36, 36 |
| 10 | combined | 10.227 | 10.324, 9.642, 10.227 | 1046.9 | 1047.2 | 24, 24, 24 |
| 10 | client | 8.737 | 8.737, 8.913, 7.831 | 1453.5 | 1589.3 | 24, 24, 24 |

Every recorded hash matched the accepted baseline. Launch attempts include duration probes; peaks include descendants and may double-count shared pages. Brief peaks may be missed. Public extraction defaults are unchanged during this experiment.
