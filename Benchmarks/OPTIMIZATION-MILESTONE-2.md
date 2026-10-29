# Optimization milestone 2 — buffers and decoder resource experiment

## Implemented and verified

- SpriteComposer, ImageProcessor, DCTProcessor, and HashComputer are synchronous Sendable structs. Processing stays on the request-owned PHash actor. Resize, grayscale, DCT, median, and bit-packing bodies are unchanged.
- Production composes its sprite incrementally, retaining the sprite and final decoded frame rather than the entire RGB frame array. AVFoundation converts each image before requesting the next and preserves the original missing-frame/conversion-error precedence and last-frame padding.
- BMP decoding reads scoped Data bytes directly, eliminating the extra encoded-byte array. Overflow-safe bounds checks reject malformed dimensions before allocation.
- A package-only extraction policy limits inputs per FFmpeg process. Groups are sequential per video. All timestamps, local stream mappings, output filenames, scaling/encoding options, and legacy whole-video fallback are preserved.
- Public APIs remain unchanged. The production input limit is now ten, selected after the purged experiment.

Release tests passed **53 tests in 14 suites** with the selected ten-input production default with the six real video fixtures. Follow-up targeted buffer tests also passed after strengthening overlap/clipping and malformed-dimension coverage. Pixel checks cover all six videos, both extraction backends, and generated portrait, VFR, multi-stream, and attached-cover fixtures. Successful group commands are traced and checked so fallback cannot mask an incorrect experiment. Late-process and late-BMP failures both discard earlier work and replay the original fast/slow fallback.

A separate read-only review found validation gaps rather than production defects; the command tracing, frozen original AV collection reference, partially populated sprite failure test, and total launch-attempt measurements address them.

## Cached resource experiment

All 24 cases matched the accepted hashes. Three rounds, six videos per case, release build, no purge. Compare policies within this experiment; these timings are not directly comparable to the accepted purged baseline.

| Inputs per process | Sequential median | Client concurrency 2 median | Client median peak tree RSS | Launch attempts per six-video case |
|---|---:|---:|---:|---:|
| Default: 25 | 10.722 s | 10.261 s | 2280 MiB | 12 |
| 1 | 19.873 s | 12.456 s | 236 MiB | 156 |
| 5 | 11.383 s | 8.226 s | 909 MiB | 36 |
| 10 | 10.227 s | 8.737 s | 1454 MiB | 24 |

Five inputs reduced median sampled tree memory about 60% for two concurrent videos, with about 20% lower median elapsed time in that mode and about 6% higher sequential time. Ten inputs reduced memory about 36% and had slightly lower sequential time. One input had the lowest sampled memory but a substantial throughput cost. Samples remain few and system conditions uncontrolled; retain all raw repetitions.

**Purged result:** the completed comparison selected ten inputs as the balanced production limit. See [selection and tradeoffs](optimization-input-groups-purged/SELECTION.md). The cached results below remain a record of the experiment before selection.

See [full experiment results](optimization-input-groups/REPORT.md), [raw measurements](optimization-input-groups/results.json), [tests](optimization-input-groups/tests.log), and [source fingerprints](optimization-input-groups/source-manifest.json).

## Completed purged checkpoint

Run from the repository root in a user Terminal:

```sh
sudo -v
python3 Benchmarks/compare_input_groups.py /Volumes/Ext-6TB-2/HashTestVids \
  --output Benchmarks/optimization-input-groups-purged \
  --policies 25 5 10 --repeats 3 --purge \
  --baseline Benchmarks/hdd-purged-2026-10-27/results.json
```

The run completed all 18 measured cases with successful purges and matching hashes. For another run, choose a new output directory. The command above now names the original 25-input control explicitly. Before the matrix it performs a checked purge and a small source-data read outside timing to reduce spin-up bias; every measured case purges again. The agent cannot supply administrator credentials. The production default is now ten inputs. [Final default-path verification](optimization-selected-default-smoke/VERIFICATION.md) passed all seven modes and confirms the effective policy in metadata.

## Scope and decisions

Work is isolated on `codex/hash-lifecycle`; previous milestone, baseline artifacts, and unrelated files are preserved. A shared FrameCollection sink retains an array path for tests/internal callers while production requests a sprite, avoiding duplicated extraction/fallback code. No new global limiter, deduplication cache, public resource-policy API, or package dependency was added. The existing baseline is immutable.
