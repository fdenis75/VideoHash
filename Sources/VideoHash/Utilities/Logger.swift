//
//  Logger.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Logging

extension Logger {
    /// Logger for VideoHash package
    static let videoHash = Logger(label: "com.videohash")

    /// Logger for OSHash generation
    static let oshash = Logger(label: "com.videohash.oshash")

    /// Logger for PHash generation
    static let phash = Logger(label: "com.videohash.phash")
}
