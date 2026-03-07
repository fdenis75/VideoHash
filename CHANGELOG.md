# Changelog

## 0.2.0
- Added batch `generateHashes(for:maxConcurrentTasks:)` API with volume-aware scheduling.
- Added `HashBatchPlanner` and tests for inter-volume planning behavior.
- Updated the `test-hash` CLI to accept a folder path and process files concurrently.
- Updated README usage examples for batch hashing and folder-based CLI runs.

## 0.1.0
- Initial public release of VideoHash.
- Added `VideoHashGenerator` API for generating PHash and OSHash.
- Added videohashes-compatible PHash mode (ffmpeg-based preprocessing).
- Added OSHash and PHash unit tests.
- Added GitHub CI workflow and contributor/security documentation.
