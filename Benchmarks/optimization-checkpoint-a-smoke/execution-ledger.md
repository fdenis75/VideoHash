# Execution ledger — plan: docs/superpowers/plans/2026-10-27-hashing-performance.md
Scope: first milestone, Tasks 1–4, as recommended and accepted in conversation.
Ruling: use a separate branch in the existing checkout to preserve the uncommitted benchmark/planning work; no worktree created.
Ruling: preserve the current uncommitted changes for review rather than automatically committing mixed baseline artifacts.
Pre-flight: Task 2 returns the existing validated asset; Task 3 introduces the runner; Task 4 extends its result with duration without changing sample timing.

Task 1: characterization passed, 3 integration tests against unchanged hashing pipeline (characterization.log).
Task 2: one validated asset returned per request; validation tests and full fixture hashes/durations pass.
Task 3: cancellation red reproduced four missing-file errors instead of CancellationError; lifecycle and integration tests now pass.
Ruling: serial queue confinement replaces the proposed mutex-only lifecycle owner, keeping Process launch/exit/cleanup off cooperative workers; audited unchecked Sendable is confined to this bridge.
Ruling: AVAssetImageGenerator must use a request-local callback bridge because Swift rejects concurrent access to its non-Sendable async interface; all 150 sampled pixels match original image(at:) output.
Task 4: bounded diagnostics tests pass including multi-MiB logs, chunk boundaries, malformed UTF-8, first-match behavior, and Unicode digits.
Final review: fresh reviewer identified deadline and active cancellation coverage gaps plus Unicode-duration discrepancy. Watchdog and active sibling/batch/AV submission tests added. Unicode discrepancy reproduced RED and fixed GREEN.
Final verification: VIDEOHASH_FIXTURE_DIR=/Users/francois/Dev/HashTestVids swift test -c release — 41 tests in 10 suites passed, 32.847 seconds, no compiler warnings.
Checkpoint A purged benchmark: pending user sudo authentication; sudo -n purge still requires password. Non-purged full-matrix smoke verification will be labelled separately.
Tasks 5–8 remain outside this first milestone; no extraction policy/algorithm changes made.

Final deadline-protected test run: 41 tests in 10 suites passed in 39.541 seconds. All seven non-purged smoke cases matched accepted hashes. Purged performance checkpoint remains pending sudo authentication.
