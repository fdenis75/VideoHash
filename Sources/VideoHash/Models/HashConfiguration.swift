//
//  HashConfiguration.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation

/// Configuration for video hash generation
public struct HashConfiguration: Sendable, Equatable {
    /// Number of frames to extract for PHash (default: 25)
    public var frameCount: Int

    /// Width to resize frames to (default: 160px)
    public var frameWidth: Int

    /// Number of columns in sprite grid (default: 5)
    public var spriteColumns: Int

    /// Number of rows in sprite grid (default: 5)
    public var spriteRows: Int

    /// DCT processing size (default: 32x32)
    public var dctSize: Int

    /// Hash size for coefficient extraction (default: 8x8)
    public var hashSize: Int

    /// Whether to use Accelerate framework for DCT (default: true)
    public var useAccelerate: Bool

    /// Whether to use ffmpeg-compatible extraction for PHash frames (default: true)
    public var useFFmpegFrameExtraction: Bool

    /// Optional path to ffmpeg binary.
    ///
    /// If nil, the executable is resolved from an app-bundled auxiliary executable first,
    /// then from PATH/common locations. In sandboxed macOS apps, prefer passing
    /// `Bundle.main.path(forAuxiliaryExecutable: "ffmpeg")`.
    public var ffmpegPath: String?

    /// Default configuration matching videohashes tool
    public static let `default` = HashConfiguration(
        frameCount: 25,
        frameWidth: 160,
        spriteColumns: 5,
        spriteRows: 5,
        dctSize: 32,
        hashSize: 8,
        useAccelerate: true,  // Use pure Swift DCT for now to debug
        useFFmpegFrameExtraction: true,
        ffmpegPath: nil
    )

    /// Initialize a hash configuration
    /// - Parameters:
    ///   - frameCount: Number of frames to extract (default: 25)
    ///   - frameWidth: Width to resize frames to (default: 160)
    ///   - spriteColumns: Sprite grid columns (default: 5)
    ///   - spriteRows: Sprite grid rows (default: 5)
    ///   - dctSize: DCT processing size (default: 32)
    ///   - hashSize: Hash coefficient size (default: 8)
    ///   - useAccelerate: Use Accelerate framework (default: true)
    ///   - useFFmpegFrameExtraction: Use ffmpeg-compatible frame extraction (default: true)
    ///   - ffmpegPath: Optional path to ffmpeg executable. In sandboxed macOS apps,
    ///     prefer `Bundle.main.path(forAuxiliaryExecutable: "ffmpeg")`.
    public init(
        frameCount: Int = 25,
        frameWidth: Int = 160,
        spriteColumns: Int = 5,
        spriteRows: Int = 5,
        dctSize: Int = 32,
        hashSize: Int = 8,
        useAccelerate: Bool = true,
        useFFmpegFrameExtraction: Bool = true,
        ffmpegPath: String? = nil
    ) {
        self.frameCount = frameCount
        self.frameWidth = frameWidth
        self.spriteColumns = spriteColumns
        self.spriteRows = spriteRows
        self.dctSize = dctSize
        self.hashSize = hashSize
        self.useAccelerate = useAccelerate
        self.useFFmpegFrameExtraction = useFFmpegFrameExtraction
        self.ffmpegPath = ffmpegPath
    }

    /// Validate configuration parameters
    public func validate() throws {
        guard frameCount > 0 else {
            throw HashError.processingFailed(reason: "Frame count must be positive")
        }
        guard frameCount == spriteColumns * spriteRows else {
            throw HashError.processingFailed(reason: "Frame count must equal sprite grid size")
        }
        guard frameWidth > 0 else {
            throw HashError.processingFailed(reason: "Frame width must be positive")
        }
        guard dctSize > 0 && dctSize.nonzeroBitCount == 1 else {
            throw HashError.processingFailed(reason: "DCT size must be power of 2")
        }
        guard hashSize > 0 && hashSize <= dctSize else {
            throw HashError.processingFailed(reason: "Hash size must be positive and <= DCT size")
        }
        if let ffmpegPath, ffmpegPath.isEmpty {
            throw HashError.processingFailed(reason: "ffmpegPath cannot be empty")
        }
    }
}
