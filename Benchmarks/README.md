# VideoHash performance baseline

The benchmark exercises the unchanged library with default configuration (FFmpeg extraction, 25 frames). It uses one shared `VideoHashGenerator` per process. Modes cover sequential combined hashes, sequential PHash and OSHash, the library batch API, and client-managed bounded task groups calling the single-video API (limits 2 and 4).

Run from the repository root:

```sh
swift test -c release
swift build -c release --product hash-benchmark
python3 Benchmarks/run.py /Users/francois/Dev/HashTestVids --output Benchmarks/new-baseline --repeats 3
python3 Benchmarks/summarize.py Benchmarks/new-baseline
```

Output directories must not already exist. Each case runs in a fresh process. JSON records include monotonic library elapsed time, per-file hashes (and individual timings where available), and sampled peak parent/process-tree RSS. The runner fails on process errors or inconsistent hashes between modes/repeats. These are regression fingerprints of this implementation, not independently certified reference hashes.

Memory is sampled using `ps` every approximately 100 ms, including FFmpeg descendants. Summed RSS can count shared pages more than once and miss short peaks; it is not a physical-footprint measurement. OSHash-only calls are particularly short, so their memory samples are not reliable. Process wall time includes startup and monitoring overhead; use the Swift-reported `seconds` for throughput comparisons. Build time is excluded.

No filesystem cache purge is performed. The first combined pass is retained separately; subsequent passes run with warmed/uncontrolled caches. Cases reverse order in the second round. Compare on the same machine, input file versions, FFmpeg build, configuration, and power conditions. Do not use these small sample sets as hard CI performance thresholds.

The benchmark does not modify files in the fixture directory. Logs may contain absolute fixture paths. The source library and hashing math are unchanged.

For later optimization runs, add `--baseline Benchmarks/baseline-2026-10-27/results.json` to also enforce unchanged hashes against this baseline. Use the same fixtures.

## Purge before each case

Run from your own Terminal so sudo can authenticate. The benchmark itself runs as your normal user; only `/usr/sbin/purge` runs with administrator privileges.

```sh
cd /Users/francois/Dev/VideoHash
sudo -v
python3 Benchmarks/run.py /Volumes/Ext-6TB-2/HashTestVids --output Benchmarks/hdd-purged-2026-10-27 --repeats 3 --purge --baseline Benchmarks/baseline-2026-10-27/results.json
python3 Benchmarks/summarize.py Benchmarks/hdd-purged-2026-10-27
```

A checked purge runs before every mode/concurrency case in every round, outside the measurement window. Each purge gets its own JSON log. Any failure stops the runner before that case starts; choose a new output directory for a retry. If sudo authorization expires during a long run, the runner stops rather than prompting or silently continuing with warm caches.

Purge affects system-wide caches. It approximates cold filesystem-cache conditions, but does not guarantee empty drive-controller caches or prevent caching within a six-video case. For a fair storage comparison, run the SSD matrix with `--purge` too.

## Integration regression tests

```sh
VIDEOHASH_FIXTURE_DIR=/Users/francois/Dev/HashTestVids swift test -c release --filter VideoHashIntegrationTests
```

Without this environment variable the video integration suite skips explicitly. With it, missing fixtures fail. The suite checks the recorded hashes/durations, shared-generator concurrent requests, batch ordering/cancellation, and AVFoundation bridge pixels/cancellation. Other tests use small deterministic temporary fixtures.

## FFmpeg input-group experiment

The public generator now uses at most ten inputs per process, selected from the purged comparison. The benchmark target can select a package-only input limit and report total FFmpeg launch attempts, including duration probes. These attempts are distinct from simultaneous child-process peaks.

```sh
python3 Benchmarks/compare_input_groups.py /Volumes/Ext-6TB-2/HashTestVids \
  --output Benchmarks/new-input-group-comparison \
  --repeats 3 --baseline Benchmarks/hdd-purged-2026-10-27/results.json
```

By default, the comparator runs sequential and client-concurrency-two cases for explicit 25-, one-, five-, and ten-input policies. The optional `default` alias follows the built production policy. Policy order reverses in alternate rounds. Each case uses a fresh process, and every hash must match the accepted baseline.

To reproduce the purged policy comparison, omit the slower one-input candidate:

```sh
sudo -v
python3 Benchmarks/compare_input_groups.py /Volumes/Ext-6TB-2/HashTestVids \
  --output Benchmarks/optimization-input-groups-purged \
  --policies 25 5 10 --repeats 3 --purge \
  --baseline Benchmarks/hdd-purged-2026-10-27/results.json
```

With `--purge`, the comparator first purges and reads 4 KiB from the middle of a source video outside measurement, reducing the chance of drive spin-up entering the first timed case. Every measured case then purges again. The preflight and each purge are recorded; failure stops the run. Device-controller caches remain uncontrolled.

For a single policy or selected cases, the underlying runner accepts `--ffmpeg-inputs 5 --cases combined-1 client-2`.

Consolidated measurements, environment records, fixture identities, reports, and selected verification logs are versioned. Verbose per-case logs and duplicate per-case JSON files remain local and are ignored by Git; the consolidated results retain their measured values and purge status.
