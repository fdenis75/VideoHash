/// Resource scheduling only: sample times and each input/output option stay unchanged.
struct FFmpegExtractionPolicy: Sendable {
    static let production = Self(fixedLimit: 9)

    let maxInputsPerProcess: Int?
    var onLaunchAttempt: (@Sendable ([String]) -> Void)?

    init() { maxInputsPerProcess = nil }

    private init(fixedLimit: Int) { maxInputsPerProcess = fixedLimit }

    init(maxInputsPerProcess: Int) throws {
        guard maxInputsPerProcess > 0 else {
            throw HashError.processingFailed(reason: "FFmpeg input limit must be greater than zero")
        }
        self.maxInputsPerProcess = maxInputsPerProcess
    }

    func groups(count: Int) -> [Range<Int>] {
        guard count > 0 else { return [] }
        let limit = maxInputsPerProcess ?? count
        return stride(from: 0, to: count, by: limit).map { start in
            start..<(start + min(limit, count - start))
        }
    }
}
