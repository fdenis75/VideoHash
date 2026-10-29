# Selected production default verification

Production now uses at most ten FFmpeg inputs per process. All 53 release tests in 14 suites passed with VIDEOHASH_FIXTURE_DIR enabled (115.185 seconds). Tests cover recorded hashes and durations, pixel parity against the original extraction, group arguments, fallback and cancellation.

The final seven-mode smoke matrix matched all accepted hashes. Each FFmpeg mode used 24 launch attempts across six videos (one duration probe plus three extraction groups per video); OSHash-only used zero. Every report and environment metadata records an effective input limit of ten. This smoke run was not purged and is not used for the performance selection; the purged comparison is in ../optimization-input-groups-purged/SELECTION.md.

Source fingerprints and the complete test log are retained beside this file. Public APIs and hash algorithms remain unchanged. Work is isolated on codex/hash-lifecycle.
