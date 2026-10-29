# Hashing performance optimization specification

## Objective

Reduce redundant metadata work, blocking waits, and peak memory while preserving the existing hashing algorithms and public entry points. Support clients that already bound concurrency and call single-video generation repeatedly on one shared generator.

## Accepted baseline

Use `Benchmarks/hdd-purged-2026-10-27/results.json` as the accepted performance baseline. All 21 cases successfully purged before measurement and matched the recorded hashes. Six fixture copies were previously verified by SHA-256. This baseline is sufficient for this work; do not expand into a new benchmarking project.

| Mode | Concurrent videos | Median seconds, six files | Maximum sampled process-tree RSS, MiB |
|---|---:|---:|---:|
| Combined sequential | 1 | 9.827 | 2545.2 |
| PHash sequential | 1 | 9.873 | 2229.5 |
| OSHash sequential | 1 | 0.250 | 8.7 |
| Library batch | 2 | 8.262 | 3395.8 |
| Client single calls | 2 | 7.862 | 3323.6 |
| Library batch | 4 | 9.901 | 3907.5 |
| Client single calls | 4 | 8.994 | 3698.8 |

RSS is sampled, includes shared-page double counting, and is not physical footprint. No physical-I/O-per-case evidence was collected. Purging does not control device caches or reuse inside a case. Three repetitions do not support tight statistical regression thresholds.

## Invariants

- Swift tools 6.2+, current macOS 26 platform floor, strict concurrency, Swift Testing, four-space indentation, one top-level type per file.
- Preserve all existing public methods, default hash configuration, return ordering, hash formatting, and successful result duration semantics.
- Do not modify OSHash arithmetic or reads, sampling timestamps, FFmpeg duration rounding/fallback, stream selection, seek semantics, scaling/color conversion, sprite placement/clipping, resize/grayscale math, DCT, coefficient selection, or median/bit packing.
- Identical final hashes are mandatory. Extraction or storage-layout changes additionally require identical decoded pixels; a matching perceptual hash alone does not prove equivalence.
- Keep FFmpeg duration probing distinct from the AVFoundation duration returned in `HashResult`.
- Cancellation is an intentional behavior improvement: cancelled work must stop, clean up resources, and throw cancellation rather than retrying extraction or returning partial results.
- Single-video calls remain caller-limited. Do not silently impose a global limit, serialize all videos, or add caching/deduplication semantics.
- Keep default FFmpeg extraction unchanged until an experimental resource policy passes both parity and benchmark evaluation.
- Do not modify input videos, overwrite baseline artifacts, or touch unrelated `testIcon/` content.

## Proposed boundaries

1. One request-owned asset, shared between validation, result metadata, and PHash. No long-lived asset cache.
2. An asynchronous subprocess runner owns launch, exit observation, cancellation, bounded diagnostic reads, and cleanup. No cooperative-worker blocking waits.
3. Pure image-processing helpers can be synchronous Sendable values. Retain public actors and explicit off-main execution through the existing per-request PHash actor.
4. Consume decoded frames into an incremental sprite, preserving order and the existing fallback restart behavior. Keep temporary BMP outputs initially; changing encoding or moving to a different decode path is out of scope.
5. Evaluate smaller sequential groups of FFmpeg inputs with the same per-frame options. This is an experiment, not an assumed win or a new public configuration API.

## Completion criteria

All existing tests plus targeted lifecycle/parity tests pass. Every V1–V6 hash matches the accepted fingerprints. Concurrent and cancelled requests clean up their owned resources. Compare staged candidates to the accepted purged HDD matrix in release mode, retaining raw results. Adopt performance changes only when benefit is credible relative to run variability; report tradeoffs rather than inventing a speedup target. A cancellation correctness improvement need not improve normal-case elapsed time.

## Deferred work

Global/shared admission control, per-volume dynamic scheduling, duplicate-request coalescing, persistent result caches, caller-supplied asset public APIs, decoder thread tuning, GPU/Accelerate rewrites, OSHash summation optimization, and disk-cache methodology changes. These need separate evidence or product/API decisions.
