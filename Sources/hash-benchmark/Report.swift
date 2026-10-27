struct Report: Codable {
    let mode: String
    let concurrency: Int
    let seconds: Double
    let measurements: [Measurement]
    let ffmpegInputsPerProcess: Int?
    let ffmpegLaunchAttempts: Int
}
