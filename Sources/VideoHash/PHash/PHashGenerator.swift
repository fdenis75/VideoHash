//
//  PHashGenerator.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Foundation
import AVFoundation
import Logging

/// Generates perceptual hash (PHash) for video files
///
/// PHash is a DCT-based image hash that represents the visual content of a video.
/// It enables finding similar or duplicate videos even if they differ in encoding,
/// resolution, or compression.
actor PHashGenerator: Sendable {
    private let configuration: HashConfiguration
    private let frameExtractor: FrameExtractor
    private let imageProcessor: ImageProcessor
    private let dctProcessor: DCTProcessor
    private let hashComputer: HashComputer
    private let logger = Logger.phash

    init(configuration: HashConfiguration, extractionPolicy: FFmpegExtractionPolicy = .production) {
        self.configuration = configuration
        self.frameExtractor = FrameExtractor(configuration: configuration, extractionPolicy: extractionPolicy)
        self.imageProcessor = ImageProcessor(configuration: configuration)
        self.dctProcessor = DCTProcessor(configuration: configuration)
        self.hashComputer = HashComputer(configuration: configuration)
    }

    /// Generate perceptual hash for a video file
    /// - Parameters:
    ///   - url: URL of the video file
    ///   - asset: Optional pre-loaded AVURLAsset (for efficiency)
    /// - Returns: Lowercase hexadecimal string representing the PHash
    /// - Throws: HashError if hash generation fails
    func generateHash(for url: URL, asset: AVURLAsset? = nil) async throws -> String {
        logger.info("Generating PHash for: \(url.path)")

        let videoAsset = asset ?? AVURLAsset(url: url)

        try Task.checkCancellation()
        logger.debug("Phase 1: Extracting frames")
        let sprite = try await frameExtractor.extractSprite(from: videoAsset, url: url)

        try Task.checkCancellation()
        logger.debug("Phase 3: Processing image")
        let pixels = try imageProcessor.processImage(sprite)

        // Phase 4: Apply DCT
        try Task.checkCancellation()
        logger.debug("Phase 4: Applying DCT")
        let dctCoeffs = try dctProcessor.applyDCT(to: pixels)

        // Phase 5: Compute hash
        try Task.checkCancellation()
        logger.debug("Phase 5: Computing hash")
        let hash = try hashComputer.computeHash(from: dctCoeffs)

        logger.info("Generated PHash: \(hash)")

        try Task.checkCancellation()
        return hash
    }
}
