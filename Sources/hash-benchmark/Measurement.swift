struct Measurement: Codable, Sendable {
    let file: String
    let seconds: Double?
    let phash: String?
    let oshash: String?
    let duration: Double?
}
