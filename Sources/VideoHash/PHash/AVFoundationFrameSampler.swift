import AVFoundation

/// Resolves sampling instants to actual presentation timestamps without assuming constant frame rate.
enum AVFoundationFrameSampler {
    /// The asset should be opened with `AVURLAssetPreferPreciseDurationAndTimingKey` enabled.
    /// Returns nil when sample cursors or edit mappings are unavailable.
    static func firstPresentationTimes(atOrAfter seconds: [Double], in asset: AVURLAsset) async throws -> [CMTime]? {
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              try await track.load(.canProvideSampleCursors) else { return nil }
        let segments = try await track.load(.segments).filter { !$0.isEmpty }.sorted {
            CMTimeCompare($0.timeMapping.target.start, $1.timeMapping.target.start) < 0
        }
        guard !segments.isEmpty else { return nil }

        return try seconds.map { seconds in
            try Task.checkCancellation()
            // FFmpeg parses -ss with microsecond precision. Preserve the selected sample's
            // rational timebase afterwards; converting it to 1/600 can select its predecessor.
            let target = CMTime(seconds: seconds, preferredTimescale: 1_000_000)
            for segment in segments {
                let mapping = segment.timeMapping
                guard CMTimeCompare(CMTimeRangeGetEnd(mapping.target), target) > 0,
                      mapping.source.duration.isNumeric, mapping.target.duration.isNumeric,
                      CMTimeCompare(mapping.source.duration, .zero) > 0,
                      CMTimeCompare(mapping.target.duration, .zero) > 0 else { continue }
                let assetTime = CMTimeMaximum(target, mapping.target.start)
                // Cursors address media time; image(at:) addresses the edited asset timeline.
                let mediaTime = CMTimeMapTimeFromRangeToRange(assetTime, fromRange: mapping.target, toRange: mapping.source)
                guard let cursor = track.makeSampleCursor(presentationTimeStamp: mediaTime) else { continue }
                // A precise cursor starts at the last sample at/before mediaTime (or the first).
                var reachedEnd = false
                while CMTimeCompare(cursor.presentationTimeStamp, mediaTime) < 0 {
                    try Task.checkCancellation()
                    if cursor.stepInPresentationOrder(byCount: 1) != 1 {
                        reachedEnd = true
                        break
                    }
                }
                guard !reachedEnd,
                      CMTimeCompare(cursor.presentationTimeStamp, CMTimeRangeGetEnd(mapping.source)) < 0 else { continue }
                return CMTimeMapTimeFromRangeToRange(cursor.presentationTimeStamp, fromRange: mapping.source, toRange: mapping.target)
            }
            // Let image generation report an unavailable frame through the existing per-frame
            // failure/normalization path instead of aborting the whole batch during planning.
            return target
        }
    }
}
