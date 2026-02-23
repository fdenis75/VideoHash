//
//  OSHashGenerator.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import Logging

/// Generates OpenSubtitles hash for video files
///
/// OSHash is a file-based hash used by OpenSubtitles.org for exact file identification.
/// It combines the file size with checksums from the first and last 64KB of the file.
public actor OSHashGenerator: Sendable {
    private static let chunkSize: Int = 65536 // 64KB
    private let logger = Logger.oshash

    /// Initialize the OSHash generator
    public init() {}

    /// Generate OpenSubtitles hash for a video file
    /// - Parameter url: URL of the video file
    /// - Returns: 16-character hex string representing the OSHash
    /// - Throws: HashError if file cannot be read or is too small
    public func generateHash(for url: URL) async throws -> String {
        let path = url.path

        // Verify file exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            logger.error("File not found: \(path)")
            throw HashError.fileNotFound(path: path)
        }

        // Get file size
        let attributes = try fileManager.attributesOfItem(atPath: path)
        guard let fileSize = attributes[.size] as? UInt64 else {
            logger.error("Could not determine file size: \(path)")
            throw HashError.invalidVideoFile(path: path, reason: "Could not determine file size")
        }

        // Verify file is large enough (must be at least 2 chunks)
        guard fileSize >= UInt64(Self.chunkSize * 2) else {
            logger.error("File too small for OSHash: \(fileSize) bytes")
            throw HashError.invalidVideoFile(
                path: path,
                reason: "File too small (minimum \(Self.chunkSize * 2) bytes)"
            )
        }

        logger.debug("Generating OSHash for: \(path) (\(fileSize) bytes)")

        // Open file for reading
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            logger.error("Could not open file: \(path)")
            throw HashError.invalidVideoFile(path: path, reason: "Could not open file for reading")
        }
        defer {
            try? fileHandle.close()
        }

        // Read first chunk
        let firstChunkData = try fileHandle.read(upToCount: Self.chunkSize) ?? Data()
        guard firstChunkData.count == Self.chunkSize else {
            logger.error("Could not read first chunk: got \(firstChunkData.count) bytes")
            throw HashError.processingFailed(reason: "Could not read first chunk")
        }

        // Seek to last chunk
        try fileHandle.seek(toOffset: fileSize - UInt64(Self.chunkSize))

        // Read last chunk
        let lastChunkData = try fileHandle.read(upToCount: Self.chunkSize) ?? Data()
        guard lastChunkData.count == Self.chunkSize else {
            logger.error("Could not read last chunk: got \(lastChunkData.count) bytes")
            throw HashError.processingFailed(reason: "Could not read last chunk")
        }

        // Calculate hash
        var hash = fileSize

        // Sum first chunk as UInt64 values
        hash = hash &+ sumChunk(firstChunkData)

        // Sum last chunk as UInt64 values
        hash = hash &+ sumChunk(lastChunkData)

        // Convert to hex string (16 characters)
        let hexString = String(format: "%016llx", hash)

        logger.debug("Generated OSHash: \(hexString)")

        return hexString
    }

    /// Sum data chunk as array of UInt64 values
    /// - Parameter data: Data chunk to sum
    /// - Returns: Sum of all UInt64 values in the chunk
    private func sumChunk(_ data: Data) -> UInt64 {
        var sum: UInt64 = 0
        let uint64Size = MemoryLayout<UInt64>.size

        // Process data in UInt64 chunks
        for offset in stride(from: 0, to: data.count, by: uint64Size) {
            var value: UInt64 = 0
            let range = offset..<min(offset + uint64Size, data.count)
            _ = withUnsafeMutableBytes(of: &value) { buffer in
                data.copyBytes(to: buffer, from: range)
            }
            sum = sum &+ value // Wrapping addition to handle overflow
        }

        return sum
    }
}
