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
    .package(url: "https://github.com/fdenis75/VideoHash.git", from: "0.1.0")
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

## Configuration

```swift
let config = HashConfiguration(
    frameCount: 25,
    frameWidth: 160,
    spriteColumns: 5,
    spriteRows: 5,
    dctSize: 32,
    hashSize: 8,
    useAccelerate: false,
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
