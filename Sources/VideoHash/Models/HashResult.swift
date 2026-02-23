//
//  HashResult.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation

/// Result containing generated video hashes and metadata
public struct HashResult: Sendable, Codable, Equatable {
    /// Perceptual hash (lowercase hexadecimal string)
    public let phash: String

    /// OpenSubtitles hash (16 hex characters)
    public let oshash: String

    /// Video duration in seconds
    public let duration: TimeInterval

    /// Date when hashes were generated
    public let generatedDate: Date

    /// Initialize a hash result
    /// - Parameters:
    ///   - phash: Perceptual hash (lowercase hexadecimal string)
    ///   - oshash: OpenSubtitles hash (16 hex characters)
    ///   - duration: Video duration in seconds
    ///   - generatedDate: Date when hashes were generated (defaults to current date)
    public init(
        phash: String,
        oshash: String,
        duration: TimeInterval,
        generatedDate: Date = Date()
    ) {
        self.phash = phash
        self.oshash = oshash
        self.duration = duration
        self.generatedDate = generatedDate
    }
}
