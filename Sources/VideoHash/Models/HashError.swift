//
//  HashError.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation

/// Errors that can occur during video hash generation
public enum HashError: LocalizedError, Sendable, Equatable {
    /// Video file not found at specified path
    case fileNotFound(path: String)

    /// Video file is invalid or cannot be read
    case invalidVideoFile(path: String, reason: String)

    /// Frame extraction failed during PHash generation
    case frameExtractionFailed(reason: String)

    /// General processing failure
    case processingFailed(reason: String)

    /// Insufficient frames extracted for PHash generation
    case insufficientFrames(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Video file not found at: \(path)"

        case .invalidVideoFile(let path, let reason):
            return "Invalid video file at \(path): \(reason)"

        case .frameExtractionFailed(let reason):
            return "Frame extraction failed: \(reason)"

        case .processingFailed(let reason):
            return "Hash generation failed: \(reason)"

        case .insufficientFrames(let expected, let actual):
            return "Insufficient frames extracted: expected \(expected), got \(actual)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .fileNotFound:
            return "Verify the file path exists and is accessible"

        case .invalidVideoFile:
            return "Ensure the file is a valid video format supported by AVFoundation"

        case .frameExtractionFailed:
            return "Check if the video is corrupted or in an unsupported format"

        case .processingFailed:
            return "Try again or check system resources"

        case .insufficientFrames:
            return "Video may be too short or corrupted"
        }
    }
}
