# VideoHash

VideoHash is a Swift package for generating video fingerprints on macOS:
- `PHash`: perceptual hash for near-duplicate detection.
- `OSHash`: OpenSubtitles hash for exact file identity.

The default PHash pipeline is compatibility-focused and matches `peolic/videohashes` output.

## Requirements

- macOS 26.0+
- Swift 6.2+
- Xcode 17+
- `ffmpeg` available on `PATH` (or set `HashConfiguration.ffmpegPath`)

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/fdenis75/VideoHash.git", from: "0.3.0")
]
```

Then add the product dependency:

```swift
.product(name: "VideoHash", package: "VideoHash")
```

## Quick Start

```swift
import VideoHash

let generator = VideoHashGenerator()
let url = URL(fileURLWithPath: "/path/to/video.mp4")
let result = try await generator.generateHashes(for: url)

print("PHash: \(result.phash)")
print("OSHash: \(result.oshash)")
print("Duration: \(Int(result.duration))s")
```

Batch hashing with controlled concurrency:

```swift
let urls: [URL] = [
    URL(fileURLWithPath: "/path/to/a.mp4"),
    URL(fileURLWithPath: "/Volumes/Archive/b.mp4")
]

let results = try await generator.generateHashes(
    for: urls,
    maxConcurrentTasks: 2
)
```

Single-video calls on one shared generator can overlap. If your client already limits concurrency, call the single-video API from that helper. Batch limits apply to each invocation independently; repeated URLs are separate jobs. On the six-video mechanical-drive benchmark, two concurrent videos was a useful starting point; measure your own workload before increasing it.

Cancelling a request throws `CancellationError`, stops extraction retries, and cleans up its owned subprocesses and temporary files. FFmpeg gets a one-second grace period before forced termination if needed. File reads and synchronous processing observe cancellation at operation boundaries. Include FFmpeg child processes when measuring memory usage. Extraction uses sequential groups of at most ten seeked inputs per FFmpeg process, limiting decoder memory without changing the sample times or hash.

Unsupported FFmpeg scaler conversions abort hashing for that video immediately with `HashError.frameExtractionFailed`; fast/accurate seeking is not retried for this error. Other extraction errors retain their existing seek fallback.

## Configuration

```swift
let config = HashConfiguration(
    frameCount: 25,
    frameWidth: 160,
    spriteColumns: 5,
    spriteRows: 5,
    dctSize: 64,
    hashSize: 8,
    useFFmpegFrameExtraction: true,
    ffmpegPath: nil
)

let generator = VideoHashGenerator(configuration: config)
```

Notes:
- `useFFmpegFrameExtraction: true` is the default and is recommended for parity with `videohashes`.
- `useFFmpegFrameExtraction: false` uses the AVFoundation/CoreGraphics path.
- `phash` is emitted as lowercase hexadecimal (not zero-padded).

## Development

```bash
swift build
swift test
swift run test-hash /path/to/video.mp4
swift run test-hash /path/to/folder 4
```

Manual parity check against the original tool:

```bash
./.build/debug/test-hash /path/to/video.mp4
/opt/bin/videohashes-amd64-macos /path/to/video.mp4
```

## Project Layout

- `Sources/VideoHash/Models`: shared models and errors
- `Sources/VideoHash/OSHash`: OSHash implementation
- `Sources/VideoHash/PHash`: PHash pipeline
- `Sources/VideoHash/Utilities`: logging helpers
- `Tests/VideoHashTests`: test suite

## License

MIT. See [LICENSE](LICENSE).

## Credits

PHash compatibility is based on [`peolic/videohashes`](https://github.com/peolic/videohashes).
