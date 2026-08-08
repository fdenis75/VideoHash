# Changelog

## 0.2.2
- Consolidated the default ffmpeg PHash preprocessing pipeline from 26 subprocess launches (25 per-frame extractions + 1 tiling pass) into a single ffmpeg process using multiple seeked inputs and a `filter_complex` graph. ~2-3x faster on real video files, up to ~8-10x on short/small ones, with identical hash output.
- Removed the lossy per-frame JPEG round-trip from the default preprocessing path.

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
