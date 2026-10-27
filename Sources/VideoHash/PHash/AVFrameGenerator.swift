import AVFoundation
import Foundation

/// Request-local bridge. Configuration, request submission, and cancellation access
/// the non-Sendable AVAssetImageGenerator only on `queue`; callbacks return images.
final class AVFrameGenerator: @unchecked Sendable {
    private let queue = DispatchQueue(label: "VideoHash.AVFrameGenerator")
    private let generator: AVAssetImageGenerator
    private var cancelled = false
    // Optional internal instrumentation, invoked on the ownership queue after submission.
    private let onSubmission: (@Sendable () -> Void)?

    init(asset: AVURLAsset, frameWidth: Int, onSubmission: (@Sendable () -> Void)? = nil) {
        self.onSubmission = onSubmission
        generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        generator.maximumSize = CGSize(width: frameWidth, height: 10_000)
    }

    func image(at time: CMTime) async throws -> CGImage {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let image: CGImage = try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !cancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, error in
                        self.queue.async {
                            if result == .cancelled {
                                continuation.resume(throwing: CancellationError())
                            } else if let image, result == .succeeded {
                                continuation.resume(returning: image)
                            } else {
                                continuation.resume(throwing: error ?? HashError.frameExtractionFailed(reason: "Image generation returned no frame"))
                            }
                        }
                    }
                    onSubmission?()
                }
            }
            try Task.checkCancellation()
            return image
        } onCancel: {
            self.queue.async { [self] in
                cancelled = true
                generator.cancelAllCGImageGeneration()
            }
        }
    }
}
