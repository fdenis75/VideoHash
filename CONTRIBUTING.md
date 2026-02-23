# Contributing

## Development setup
1. Install Swift 6.2+ and Xcode 17+.
2. Install `ffmpeg` and ensure it is on `PATH`.
3. Clone the repository and build:
   ```bash
   swift build
   ```

## Running tests
Run the full test suite before opening a PR:
```bash
swift test
```

For manual parity checks against `videohashes`:
```bash
./.build/debug/test-hash /path/to/video.mp4
/opt/bin/videohashes-amd64-macos /path/to/video.mp4
```

## Code style
- Follow Swift API Design Guidelines.
- Prefer small focused types and clear error messages.
- Keep concurrency-safe code (`Sendable`, actors) where shared state exists.
- Add tests for bug fixes and behavior changes.

## Pull requests
Please include:
- A short problem statement and solution summary.
- Notes on API changes (if any).
- Evidence of validation (`swift test` output, and parity checks when PHash logic changes).

## Commit messages
Use imperative subject lines, for example:
- `Fix frame sampling to match videohashes`
- `Add ffmpeg-based preprocessing path`
