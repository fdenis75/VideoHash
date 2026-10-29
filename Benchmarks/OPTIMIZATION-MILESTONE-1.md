# Optimization milestone 1 — lifecycle and redundant work

Branch: `codex/hash-lifecycle`. Scope: plan Tasks 1–4. Work is isolated on this branch; baseline artifacts and unrelated `testIcon/` files are preserved.

## Implemented

- Validation returns its AVURLAsset for reuse by result metadata and PHash. Combined and PHash-only requests now construct one asset instead of two. OSHash remains asset-free.
- FFmpeg exit observation uses a continuation and a request-owned serial lifecycle queue; no `waitUntilExit()` or detached blocking wait remains in the library.
- Cancellation prevents new extraction/fallback work, terminates active FFmpeg, escalates after a one-second grace period if needed, and waits for exit before cleaning temporary files and resuming the caller.
- AVFoundation request submission/cancellation uses a queue-confined callback bridge. Public actors and caller-managed concurrency are unchanged.
- Diagnostic logs retain at most 64 KiB of head and 64 KiB of tail, with bounded chunk scanning for duration independently of the excerpt. UTF-8 validity and first-match Unicode-digit behavior are preserved. Diagnostic disk output itself is not capped.
- Regression tests cover recorded hashes/durations, duplicate concurrent requests, batch ordering, process lifecycle races/cleanup, active sibling and batch cancellation, AV submission cancellation, diagnostic boundaries, and pixel equivalence.

Hash arithmetic, frame timestamps, FFmpeg arguments/options, extraction batching, sprite/image/DCT processing, and output formats are unchanged. Actor simplification, frame-buffer streaming, and FFmpeg input-group experiments are later milestones.

## Validation

`VIDEOHASH_FIXTURE_DIR=/Users/francois/Dev/HashTestVids swift test -c release` passed 41 tests in 10 suites. The integration suite verifies all six videos and all 150 AVFoundation sampled frames against the original image API. Compiler diagnostics were warning-free.

A separate reviewer examined lifecycle and duration behavior. Their findings were addressed: cancellation tests now have real deadlines with process cleanup, active request isolation is tested, and a Unicode-duration discrepancy was reproduced with a failing test and fixed.

The seven-case smoke matrix also passed every hash comparison against `hdd-purged-2026-10-27/results.json`. See [raw smoke measurements](optimization-checkpoint-a-smoke/results.json), [environment](optimization-checkpoint-a-smoke/environment.json), and [source fingerprints](optimization-checkpoint-a-smoke/source-manifest.json).

The smoke run has one repetition and **no cache purge**. It is not evidence of a speedup or memory reduction against the accepted baseline. The matching purged checkpoint is now complete; see [the comparison](optimization-checkpoint-a-purged/REPORT.md). Timing results are mixed and concurrent process-tree memory increased.

## Purged checkpoint A

Completed with 21 successful purges and matching hashes. The command below documents reproduction; use a new output directory for another run:

```sh
cd /Users/francois/Dev/VideoHash
sudo -v
python3 Benchmarks/run.py /Volumes/Ext-6TB-2/HashTestVids \
  --output Benchmarks/optimization-checkpoint-a-purged \
  --repeats 3 --purge \
  --baseline Benchmarks/hdd-purged-2026-10-27/results.json
```

Each successful purge is recorded and excluded from timing; the runner stops if sudo authorization expires. The comparison is recorded in `optimization-checkpoint-a-purged/REPORT.md`; carry its concurrent-memory regression into the next milestone. The original baseline remains unchanged.

## Implementation decisions

- Used a separate branch in the existing checkout to preserve the current uncommitted baseline/planning work; no worktree was created. The final commit excludes unrelated pre-existing work.
- Queue confinement replaces the plan's proposed mutex-only process owner, so launch, exit, and diagnostic file I/O do not block Swift cooperative workers. The two Foundation lifecycle bridges document their narrow unchecked Sendable invariants.
- AVFoundation required a callback bridge because its raw async image generator is not Sendable when concurrently cancelled. Pixel parity and cancellation tests cover that change.
- No new global limiter, deduplication cache, public API, or dependency was added.
