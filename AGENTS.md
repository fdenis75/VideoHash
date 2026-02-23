# Repository Guidelines

## Project Structure & Module Organization
This repository is a Swift Package (`Package.swift`) with one library and one CLI target:
- `Sources/VideoHash/`: core library code.
- `Sources/VideoHash/Models/`: shared types (`HashResult`, `HashError`, `HashConfiguration`).
- `Sources/VideoHash/OSHash/` and `Sources/VideoHash/PHash/`: hash algorithm implementations.
- `Sources/VideoHash/Utilities/`: logging helpers.
- `Sources/TestHash/main.swift`: executable target for local manual checks.
- `Tests/VideoHashTests/`: automated tests (currently OSHash-focused).
- `.build/`: local build artifacts (do not edit or commit).

## Build, Test, and Development Commands
Run from repository root:
- `swift build`: compile all targets in debug mode.
- `swift test`: run the test suite.
- `swift run test-hash /absolute/path/to/video.mp4`: run both hashes against a real video file.
- `swift package resolve`: refresh dependency resolution when package versions change.

## Coding Style & Naming Conventions
- Swift 6.2+ and strict concurrency are enabled; prefer `async/await`, `Sendable`, and actors for shared mutable state.
- Use 4-space indentation and keep one top-level type per file.
- Type names use `UpperCamelCase`; methods/properties use `lowerCamelCase`.
- Organize new code by feature folder (`Models`, `OSHash`, `PHash`, `Utilities`) rather than by file type.
- Keep public APIs documented with concise doc comments.

## Testing Guidelines
- Tests use Swift Testing (`import Testing`) with `@Suite` and `@Test`.
- Name tests by behavior, e.g. `testHashFormat`, `testDeterministic`.
- Prefer deterministic test data and temporary files; always clean up with `defer`.
- Add tests for success paths, error handling, and edge constraints (file size, invalid paths, malformed input).

## Commit & Pull Request Guidelines
Local git metadata is not present in this package snapshot, so no repository-specific commit history could be inferred. Use this baseline:
- Commit style: imperative, concise subject (<=72 chars), e.g. `Add validation for short OSHash inputs`.
- Keep commits scoped to one logical change.
- PRs should include: purpose, behavior changes, test evidence (`swift test` output), and sample CLI usage when relevant.
