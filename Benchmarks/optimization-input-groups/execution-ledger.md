# Execution ledger — plan: docs/superpowers/plans/2026-10-27-hashing-performance.md
Continuing Tasks 5–8 on codex/hash-lifecycle; all earlier uncommitted work preserved.
Accepted checkpoint A purged run: matching hashes; concurrent decoder RSS increased. Prioritize measured resource bounds after safe buffer refactoring.

Task 5: synchronous test calls failed against actor helpers; helper wrappers converted to Sendable structs; reference/unit suite GREEN (41 tests).
Task 6: missing accumulator interfaces RED; incremental storage implemented; BMP reads use scoped raw bytes with overflow-safe size validation. Array extraction retained only for parity/internal callers. Both backends compared to array/legacy collect-normalize-convert pixels on all six fixtures.
Ruling: FrameCollection is a shared sink for production sprites and test frame arrays, avoiding duplicated extraction/seek/fallback code. append cannot fail; finish validates counts.
Task 7: group scheduling tests RED (missing type) then GREEN. Package-only policy hook; public default remains all inputs. Group failures restart legacy fallback across all samples.
Final review identified validation gaps: added exact successful command traces/no fallback, frozen original AV collection reference, and malformed-later-BMP fallback after partial sprite accumulation. Added launch-attempt count instead of confusing simultaneous child peaks with total launches.
Verification: 52 tests in 14 suites passed in release mode with fixture directory, 107.303 seconds, warning-free compiler. Only expected fake-failure warnings occur in fallback tests.
Ruling: purged checkpoint B requires user sudo authentication, so evaluate cached resource candidates now and prepare a single repeatable purged comparison rather than require multiple user authentication steps. No new extraction default may ship on cached timings alone.

Final experiment: all 24 cached cases matched accepted hashes; 3 rounds across default/1/5/10 policies and sequential/client-2 modes. Default client median 10.261s, 2280MiB; 5 inputs 8.226s, 909MiB; 10 inputs 8.737s, 1454MiB. One input rejected for throughput. No production default changed.
Task 8: client concurrency/cancellation guidance and repeatable experiment commands documented. Next purged comparison selects default/5/10, 18 cases. It requests a preflight source read after a purge to reduce drive wake-up bias before measurement.
Final targeted tests: strengthened overlapping/clipped frames and BMP overflow dimensions; 4 SpriteAccumulatorTests pass. Production source unchanged after the 52-test integration pass and experiment.
Purged orchestrator preflight failure/success guards and forwarding validated with simulated subprocess outcomes; actual purging requires user authentication.
