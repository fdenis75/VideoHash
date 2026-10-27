# Hashing Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce resource use and redundant work without changing either hashing algorithm or breaking client-managed concurrency.

**Architecture:** Keep public actors and request-local ownership. Reuse one AVURLAsset per video request, bridge subprocess completion asynchronously, and shorten buffer lifetimes. Evaluate FFmpeg input grouping separately from the low-risk changes; do not assume fewer subprocess launches means lower memory.

**Tech Stack:** Swift 6.2+, macOS 26+, Swift Testing, Foundation Process, AVFoundation, existing Python benchmark tools; no new package dependencies.

**Spec:** `docs/superpowers/specs/2026-10-27-hashing-performance.md`.

## Global Constraints

- Hash algorithms and all pixel/sampling semantics are frozen as specified in the linked spec.
- Preserve public methods and actors, batch ordering, and the default configuration.
- Single-video concurrency is controlled by the client; the existing batch limit applies per batch invocation.
- Keep the accepted baseline immutable: `Benchmarks/hdd-purged-2026-10-27/results.json`.
- Use request-owned resources, strict concurrency, four-space indentation, and one top-level type per file.
- Do not commit unrelated work. Existing benchmark files and Package.swift changes predate this plan and must be preserved.
- If implementation uses a worktree, remove its build artifacts/derived data before completing work, per repository instructions.

## Review Focus

1. Cancellation racing process launch/exit must resume exactly once and leave no subprocess, open handle, or temporary file behind (Task 3).
2. Noisy/corrupt input must not deadlock, allocate an entire stderr file, or lose a valid duration line because diagnostics were truncated (Task 4).
3. Concurrent calls on one public generator—including the same URL—must have isolated temporary files, correct results, and no accidental global serialization (Tasks 1 and 3).
4. Late extraction failure and inconsistent frame dimensions must preserve restart, order, clipping, and frame duplication semantics (Tasks 6 and 7).
5. AVFoundation extraction cancellation must propagate rather than being swallowed as a missing frame; backend-specific pixel behavior must remain unchanged (Tasks 3 and 6).

## Current status

Tasks 1–8 are implemented. The purged input-group comparison completed 18 cases with successful purges and unchanged hashes. Ten inputs is selected for production: roughly 49% lower median tree RSS and 10% lower elapsed time with two concurrent videos, with a roughly 6% sequential cost in this sample. Final default-path verification passed: 53 tests in 14 suites and all seven benchmark modes matched the accepted hashes. See [milestone 1](../../../Benchmarks/OPTIMIZATION-MILESTONE-1.md), [milestone 2](../../../Benchmarks/OPTIMIZATION-MILESTONE-2.md), and [policy selection](../../../Benchmarks/optimization-input-groups-purged/SELECTION.md).

## Delivery and evaluation order

Land Tasks 1–4 first. They provide regression protection, asset reuse, and reliable lifecycle behavior without altering extraction scheduling. Then Tasks 5–6 simplify internal isolation and buffer ownership. Task 7 is experimental and independently rejectable. Task 8 records the selected result and client guidance.

Run targeted tests after each task, the full release suite at each checkpoint, and the full fixture benchmark after Tasks 4, 6, and any Task 7 candidate worth considering. Keep changes attributable; do not stack an unverified extraction experiment onto other work.

### Task 1: Pin end-to-end parity and concurrency behavior

**Files:**
- Create `Tests/VideoHashTests/VideoHashIntegrationTests.swift`.
- Create `Tests/VideoHashTests/Fixtures/video-hashes.json` and add only this resource to the test target in `Package.swift`.
- Modify `Benchmarks/README.md` with integration-test invocation.

**Interfaces:** Optional `VIDEOHASH_FIXTURE_DIR` environment variable enables integration tests; absent means explicitly skipped, supplied but invalid means failure. The JSON manifest stores V1–V6 filenames, SHA-256 identities, PHash, OSHash, and AVFoundation result durations copied from existing artifacts. It does not embed videos or generatedDate values.

- [ ] Add tests asserting combined/PHash-only/OSHash-only outputs equal the manifest, and combined durations remain unchanged on this machine/toolchain.
- [ ] Add `testConcurrentSingleCallsPreserveResults` with one shared public generator and a bounded two-task group. Include two requests for the same file; assert both results, ignoring generatedDate. Do not expect deduplication.
- [ ] Add `testBatchPreservesInputOrder` using a deliberately shuffled input array and limit two.
- [ ] Run `VIDEOHASH_FIXTURE_DIR=/Users/francois/Dev/HashTestVids swift test -c release --filter VideoHashIntegrationTests`; expect all manifest assertions to pass on the unchanged implementation. This is characterization, not an expected failing test.
- [ ] Run `swift test -c release`; expect the existing 20 tests to pass and fixture-dependent tests to skip clearly when no environment variable is supplied.
- [ ] Review and commit only these regression protections.

### Task 2: Reuse the asset within each video request

**Files:** Modify `Sources/VideoHash/VideoHash.swift`; extend `VideoHashIntegrationTests.swift`.

**Interfaces:** Replace `validateVideoFile(_:) async throws -> Void` with `validatedAsset(for url: URL) async throws -> AVURLAsset`. Combined and PHash-only helpers consume the returned asset. OSHash-only stays asset-free.

- [ ] Preserve file existence/readability checks and track validation; return the asset whose tracks were loaded instead of discarding it.
- [ ] Remove the second construction in both callers. Pass the same asset into PHash; keep AVFoundation result-duration loading and FFmpeg sample-duration probing separate.
- [ ] Add missing-file and non-video-input tests for the affected public entry points; assert current error categories remain unchanged.
- [ ] Run targeted integration tests and `swift test -c release`. Inspect the production path to confirm one asset construction per combined/PHash request and none for OSHash.
- [ ] Review and commit the asset-lifetime change. Do not add a global asset cache or a public overload.

### Task 3: Make process waiting asynchronous and cancellation effective

**Files:**
- Create `Sources/VideoHash/PHash/FFmpegProcessRunner.swift`, `FFmpegProcessResult.swift`, and `ProcessExecution.swift` (runner API, value result, synchronized lifecycle owner respectively).
- Modify `FrameExtractor.swift`, `PHashGenerator.swift`, `VideoHash.swift`, and `OSHash/OSHashGenerator.swift` only for cancellation boundaries in the latter two.
- Create `Tests/VideoHashTests/FFmpegProcessRunnerTests.swift` and `FrameExtractionCancellationTests.swift`.

**Interfaces:**
- `FFmpegProcessRunner.run(executableURL: URL, arguments: [String]) async throws -> FFmpegProcessResult`.
- Initially `FFmpegProcessResult: Sendable` holds `status: Int32` and `stderr: String`; Task 4 adds parsed duration.
- Private lifecycle owner synchronizes launch/exit/cancellation/continuation state. Use a narrowly scoped mutex; never hold it across await or process termination waits. Any unchecked Sendable conformance must document this ownership and synchronization invariant.

- [ ] Write subprocess tests using temporary executable fixtures: successful exit, nonzero exit, nonexistent executable, cancellation before launch, cancellation during execution, and exit racing cancellation. Assert exactly one completion and removal of owned temporary files/handles; use readiness markers rather than sleep-based race assumptions.
- [ ] Add a fixture that ignores graceful termination. Define cancellation as graceful termination followed by forced termination after a one-second grace period if the owned process remains alive; await exit observation before releasing resources. Tests use a five-second outer deadline solely to detect a stuck lifecycle.
- [ ] Implement termination-handler/continuation waiting with handlers installed before launch. Serialize lifecycle bookkeeping off the cooperative executor where necessary; remove `waitUntilExit()` rather than hiding it in `Task.detached`.
- [ ] Make duration probe, batch extraction, and per-frame extraction await the runner. Preserve expected nonzero duration-probe exits and existing launch/exit HashError mappings; propagate CancellationError unchanged.
- [ ] Check cancellation at request entry and between extraction/processing phases. In fallback catches, check cancellation before retrying; cancellation must never launch the next FFmpeg process. OSHash checks only at operation boundaries; do not change its arithmetic/read loop.
- [ ] Add cancellation forwarding to the request-owned AVAssetImageGenerator, including cancellation before generation starts. Re-throw cancellation in the per-frame catch before handling ordinary frame failures.
- [ ] Verify cancelled batch children eventually terminate and clean up, while cancelling one independently launched client request does not cancel its sibling. Test with controllable extraction fixtures.
- [ ] Run `swift test -c release --filter 'FFmpegProcessRunnerTests|FrameExtractionCancellationTests'`, integration parity tests, and full release tests. Run multiple process fixtures concurrently to verify waiting suspends rather than occupying a worker until exit.
- [ ] Review and commit lifecycle changes separately from the diagnostic-memory optimization.

### Task 4: Bound stderr memory without changing duration selection

**Files:** Modify `FFmpegProcessRunner.swift`, `FFmpegProcessResult.swift`, and `FrameExtractor.swift`; create `FFmpegDiagnostics.swift` and `Tests/VideoHashTests/FFmpegDiagnosticsTests.swift`.

**Interfaces:** Add `reportedDuration: Double?` to `FFmpegProcessResult`. `FFmpegDiagnostics.read(from url: URL) throws -> (excerpt: String, reportedDuration: Double?)` scans the stderr file in 64 KiB chunks, retains at most 64 KiB of head plus 64 KiB of tail, and identifies duration independently of the retained excerpt.

- [ ] Write tests for stderr larger than 1 MiB, a duration beyond both retained regions, a duration split across chunk boundaries, malformed UTF-8, missing duration, and a process emitting more than pipe capacity. Assert bounded excerpt size plus an explicit truncation marker, no deadlock, and the same centisecond duration as the existing parser.
- [ ] Keep stderr redirected to a temporary file initially. Replace the full `Data(contentsOf:)`/String read with bounded scanning; preserve the existing parser's first matching duration behavior, including AVFoundation fallback if the match is unusable. Do not substitute the excerpt for the parse source.
- [ ] Ensure temporary logs are cleaned on success, launch failure, nonzero exit, and cancellation. This bounds RAM, not total diagnostic disk output; document that distinction.
- [ ] Run diagnostic and lifecycle tests, integration parity, and the full release suite.
- [ ] Run checkpoint A using the benchmark procedure below. Save new raw artifacts; no hash mismatches are acceptable.
- [ ] Review and commit bounded diagnostic handling.

### Task 5: Remove unnecessary isolation from pure processing stages

**Files:** Modify `SpriteComposer.swift`, `ImageProcessor.swift`, `DCTProcessor.swift`, `HashComputer.swift`, `PHashGenerator.swift`, and affected unit tests.

**Interfaces:** Change the four pure helper actors into internal `Sendable` structs with the same initializers and synchronous throwing methods: `composeSprite(from:)`, `processImage(_:)`, `applyDCT(to:)`, `computeHash(from:)`. Retain public actors, the per-request PHashGenerator actor, and FrameExtractor isolation.

- [ ] Remove actor/async wrappers and corresponding awaits only. Do not edit the bodies of resizing, grayscale, DCT, median, packing, or sprite copy logic.
- [ ] Keep synchronous CPU processing on the PHashGenerator actor rather than moving it onto a calling MainActor. No mutable shared scratch buffers or global processor singletons.
- [ ] Update internal test calls and run the existing synthetic reference-parity suite plus integration parity. Strict concurrency must compile without new warnings or unchecked conformances in these value helpers.
- [ ] Review and commit the wrapper-only change. Do not claim material memory savings from eliminating a handful of actor objects.

### Task 6: Reduce frame-buffer copies and overlap

**Files:** Modify `BMPDecoder.swift`, `FrameExtractor.swift`, `SpriteComposer.swift`, `PHashGenerator.swift`; create `SpriteAccumulator.swift`, `SpriteAccumulatorTests.swift`; extend `PHashReferenceParityTests.swift` and cancellation tests.

**Interfaces:**
- Keep `BMPDecoder.decode(_ data: Data) throws -> RGBImage`.
- `SpriteAccumulator.init(configuration: HashConfiguration)`, `mutating append(_ frame: RGBImage) throws`, `finish() throws -> RGBImage`.
- `FrameExtractor.extractSprite(from asset: AVURLAsset, url: URL) async throws -> RGBImage` replaces its internal array-producing interface for the production pipeline.

- [ ] Add pixel-exact tests for top-down/bottom-up BMPs, padding, truncated headers/data, mixed frame sizes, canvas-edge clipping, and insufficient frames. Assert streaming composition equals the original all-frame composition byte-for-byte.
- [ ] Decode BMP bytes through scoped `Data.withUnsafeBytes`, removing `[UInt8](data)` without changing BGR conversion or row order. Do not retain unsafe pointers outside the closure.
- [ ] Move the existing placement/copy behavior into the accumulator without changing arithmetic. Define the cell from the first frame, preserve input order and canvas-bound clipping, and finalize only at the existing required frame count.
- [ ] For FFmpeg, finish batch extraction first, then read/decode/append/release one BMP at a time. If decoding or extraction requires fallback, discard any partial accumulator and restart all sample times using the existing fast-to-slow seek rules.
- [ ] For AVFoundation, convert and append each successful CGImage before requesting the next. Track successful-frame count and the final successful frame; preserve the existing minimum count and duplicate-last-frame normalization. If RGB conversion fails, retain the first conversion error while continuing the image-count checks; preserve the original insufficient-frames-before-conversion-error precedence. Cancellation still propagates immediately.
- [ ] Keep scoped conversions short; consider local autorelease pools only around synchronous Foundation/CoreGraphics work, never across await. No assumption that Swift arrays are freed solely because source scope ended.
- [ ] Run pixel tests, failure/restart tests, cancellation tests, all release tests, and fixture parity for both extraction backends. Capture AVFoundation backend expectations from the old path before replacing it; do not compare its hashes to FFmpeg hashes.
- [ ] Run checkpoint B. Compare parent and process-tree RSS separately; expected Swift-side savings are modest relative to FFmpeg decoder memory.
- [ ] Review and commit storage/lifetime changes without modifying processing algorithms.

### Task 7: Experiment with bounded FFmpeg input groups

**Files:** Modify `FrameExtractor.swift`, `PHashGenerator.swift`, `VideoHash.swift`, `Sources/hash-benchmark/main.swift`, and `Benchmarks/run.py`; create internal `FFmpegExtractionPolicy.swift`, `FFmpegExtractionPolicyTests.swift`, and opt-in `FrameExtractionParityTests.swift`.

**Interfaces:** Internal policy has `maxInputsPerProcess: Int?`, where nil means the existing all-input batch. Production remains nil during evaluation. Add `package init(configuration: HashConfiguration, ffmpegMaxInputsPerProcess: Int) throws` to VideoHashGenerator for the benchmark target; it validates a positive limit and passes a request-local policy through its static helpers, PHashGenerator, and FrameExtractor. Keep the public initializer selecting nil. Extend the executable with an optional final max-inputs argument and the runner with `--ffmpeg-inputs`; record it in environment and run JSON. Benchmark candidates use 1, 5, and 10 inputs per process, sequential groups per video; no simultaneous groups inside one video.

- [ ] Add tests asserting each sample is scheduled exactly once in successful groups, global output order is unchanged, and argument mapping uses the group's local input indices with the original timestamps/options.
- [ ] Add a controlled late-group failure. Assert prior outputs are discarded and extraction restarts the whole video using the original fallback sequence; do not silently mix successful groups with a different fallback history.
- [ ] Implement grouping around the unchanged per-frame seek/map/scale/BMP options. Do not tune decoder threads, replace 25 seeks with linear sampling, or change the default stream selector.
- [ ] Compare decoded RGB pixels for every sample against the original all-input path on V1–V6, plus generated cover-art, variable-frame-rate, portrait, and multi-video-stream fixtures. Final hashes must match too. Reject any candidate that changes pixels or fallback semantics.
- [ ] Measure viable candidates in release mode at video concurrency one and two first. Record process count, time, parent RSS, and process-tree RSS. Test concurrency four only if a candidate shows a useful tradeoff; keep the baseline settings available for direct comparison.
- [ ] Select a candidate only if it offers a credible memory/throughput benefit on repeat measurements. If lower memory costs meaningful throughput, present both measurements before choosing a new default. If none wins, keep current extraction and document the negative result.
- [ ] Review the experiment independently; do not ship an arbitrary five-input default just because it was a test candidate.

### Task 8: Final validation and client guidance

**Files:** Modify `README.md`, `Benchmarks/README.md`; create a dated optimization report beside, not inside, baseline directories.

- [ ] Document that one shared VideoHashGenerator supports overlapping single requests, public actors are not admission limits, multiple batches have independent limits, and duplicate URLs remain separate jobs.
- [ ] Recommend concurrency two as the measured starting point for these HDD fixtures, not a universal default or enforced limit. Explain process cancellation and ownership.
- [ ] Run full release tests, opt-in fixture parity, and the unchanged full purged HDD benchmark matrix with baseline checking. Include whichever extraction policy actually ships.
- [ ] Compare all seven modes to the accepted baseline. Investigate median regressions beyond the observed run-to-run spread; no hard percentage threshold is justified by three samples. Retain accepted lifecycle fixes even if they are timing-neutral.
- [ ] Record exact changes, hashes, tests, raw run paths, memory/time tradeoffs, and remaining limitations. Check `git diff --check` and confirm algorithm bodies and unrelated files are unchanged.
- [ ] Review and commit the selected implementation and documentation in scoped commits. Clean worktree build outputs if applicable.

## Benchmark checkpoint procedure

Build first, outside timing:

```sh
swift test -c release
swift build -c release --product hash-benchmark
VIDEOHASH_FIXTURE_DIR=/Users/francois/Dev/HashTestVids swift test -c release --filter VideoHashIntegrationTests
```

In a user Terminal with administrator authentication, use a new output directory per checkpoint/candidate:

```sh
sudo -v
python3 Benchmarks/run.py /Volumes/Ext-6TB-2/HashTestVids \
  --output Benchmarks/optimization-checkpoint-a \
  --repeats 3 --purge \
  --baseline Benchmarks/hdd-purged-2026-10-27/results.json
python3 Benchmarks/summarize.py Benchmarks/optimization-checkpoint-a
```

Purge privilege requirements were verified in this session: direct purge is denied and this agent cannot supply sudo credentials. Preparation, tests, and non-purged smoke checks can proceed autonomously; the purged measurement itself must use a successfully authenticated invocation. Never silently substitute warm-cache results.

## Deferred decisions

No global limiter or in-flight deduplication in this plan. A single shared OSHashGenerator currently serializes direct calls because its operation has no suspension points; preserve that API behavior. OSHash blocking file reads may merit a dedicated I/O adapter later if profiling on slow/network storage shows worker starvation. Do not rewrite its efficient 128 KiB read path speculatively.
