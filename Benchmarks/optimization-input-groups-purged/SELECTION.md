# Production policy selection: ten FFmpeg inputs per process

The purged comparison completed all 18 cases. All hashes match the accepted baseline, all 18 case purges succeeded, and the initial purge/source-data-read preflight completed outside timing. Raw records are in `results.json`; full three-round measurements are in `REPORT.md`.

| Inputs/process | Sequential median | Client concurrency 2 median | Client median peak tree RSS |
|---|---:|---:|---:|
| Original: 25 | 9.709 s | 9.185 s | 2803 MiB |
| 5 | 11.276 s | 8.908 s | 923 MiB |
| Selected: 10 | 10.325 s | 8.258 s | 1430 MiB |

Ten inputs reduced median sampled process-tree memory about 49% and client-concurrency-two elapsed time about 10%. Sequential elapsed time increased about 6%. Five inputs reduced memory about 67%, but sequential elapsed time increased about 16%, and client time improved only about 3%. Ten is selected as the balanced production limit.

The original sequential policy had one 13.744 s repetition; all samples are retained. Three repetitions and sampled RSS do not justify tight performance guarantees. Disk-controller caches, system load, thermal conditions, and brief memory peaks remain uncontrolled.

Only process grouping changes. Default 25-frame sampling becomes sequential groups of 10, 10, and 5 inputs per video, preserving every timestamp, stream mapping, decode/scale/BMP option, output order, and whole-video fallback. Hash configuration, arithmetic, and public API stay unchanged. Client concurrency remains client-controlled.

For future comparisons the benchmark reports its effective input limit. Use `--ffmpeg-inputs 25` or comparator `--policies 25 5 10` to reproduce the original policy explicitly; `default` now means the production ten-input policy. Historical `default (25)` rows describe the policy at the time of this experiment.

Final verification after selection: 53 release tests passed, and all seven benchmark modes matched the recorded hashes with an effective ten-input default. See `../optimization-selected-default-smoke/VERIFICATION.md`.
