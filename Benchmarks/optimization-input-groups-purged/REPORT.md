# FFmpeg input grouping experiment

Release build. Successful purge required before each case. Selected policies are run sequentially, with policy order reversed in alternate rounds. Each case hashes the fixture corpus.

| Inputs per process | Mode | Median seconds | Runs (seconds) | Median peak tree RSS (MiB) | Max peak tree RSS (MiB) | FFmpeg launch attempts per case |
|---|---|---:|---|---:|---:|---|
| default (25) | combined | 9.709 | 9.660, 9.709, 13.744 | 2217.0 | 2228.9 | 12, 12, 12 |
| default (25) | client | 9.185 | 7.963, 9.387, 9.185 | 2802.8 | 3066.7 | 12, 12, 12 |
| 5 | combined | 11.276 | 11.097, 11.276, 11.952 | 564.6 | 569.5 | 36, 36, 36 |
| 5 | client | 8.908 | 8.881, 8.908, 9.796 | 922.5 | 928.1 | 36, 36, 36 |
| 10 | combined | 10.325 | 11.070, 10.254, 10.325 | 1062.8 | 1063.2 | 24, 24, 24 |
| 10 | client | 8.258 | 8.258, 7.921, 8.585 | 1429.8 | 1477.5 | 24, 24, 24 |

Every recorded hash matched the accepted baseline. Launch attempts include duration probes; peaks include descendants and may double-count shared pages. Brief peaks may be missed. Public extraction defaults are unchanged during this experiment.
