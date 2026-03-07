//
//  HashBatchPlanner.swift
//  VideoHash
//
//  Created by Codex on 07/03/2026.
//

import Foundation

/// Produces a stable, volume-aware batch order for video hashing.
struct HashBatchPlanner {
    struct Item: Sendable, Equatable {
        let originalIndex: Int
        let url: URL
        let volumeKey: String
    }

    static func makePlan(
        for urls: [URL],
        volumeResolver: (URL) -> String = resolveVolumeKey(for:)
    ) -> [Item] {
        guard !urls.isEmpty else { return [] }

        var buckets: [String: [Item]] = [:]
        var volumeOrder: [String] = []

        for (index, url) in urls.enumerated() {
            let volumeKey = volumeResolver(url)
            if buckets[volumeKey] == nil {
                buckets[volumeKey] = []
                volumeOrder.append(volumeKey)
            }
            buckets[volumeKey]?.append(
                Item(
                    originalIndex: index,
                    url: url,
                    volumeKey: volumeKey
                )
            )
        }

        var positions = Dictionary(uniqueKeysWithValues: volumeOrder.map { ($0, 0) })
        var plan: [Item] = []
        plan.reserveCapacity(urls.count)

        while plan.count < urls.count {
            for volumeKey in volumeOrder {
                guard let bucket = buckets[volumeKey], let position = positions[volumeKey] else {
                    continue
                }

                guard position < bucket.count else {
                    continue
                }

                plan.append(bucket[position])
                positions[volumeKey] = position + 1
            }
        }

        return plan
    }

    static func resolveVolumeKey(for url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey, .volumeNameKey]) {
            if let volumeIdentifier = values.volumeIdentifier {
                return String(describing: volumeIdentifier)
            }
            if let volumeName = values.volumeName {
                return volumeName
            }
        }

        let components = url.standardizedFileURL.pathComponents
        if components.count > 2, components[1] == "Volumes" {
            return "/Volumes/\(components[2])"
        }

        return "/"
    }
}
