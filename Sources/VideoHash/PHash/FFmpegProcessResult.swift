struct FFmpegProcessResult: Sendable {
    let status: Int32
    let stderr: String
    let reportedDuration: Double?
}
