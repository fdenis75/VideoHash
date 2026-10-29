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

/// Hands out a plan's items one at a time, each from the volume with the
/// fewest files in flight (ties broken round-robin, so the first picks follow
/// the plan), keeping each volume's own order. A fixed interleaved order
/// isn't enough: once a fast volume's files keep finishing first, the next
/// items in line belong to the slow one, until every slot is on the slow
/// volume and the fast one sits idle.
struct VolumeBalancedQueue {
    private var buckets: [[HashBatchPlanner.Item]] = []
    private var positions: [Int] = []
    private var inFlight: [Int] = []
    private var bucketOfIndex: [Int: Int] = [:]
    private var lastPicked = -1

    init(plan: [HashBatchPlanner.Item]) {
        var bucketOfKey: [String: Int] = [:]
        for item in plan {
            let bucket: Int
            if let existing = bucketOfKey[item.volumeKey] {
                bucket = existing
            } else {
                bucket = buckets.count
                bucketOfKey[item.volumeKey] = bucket
                buckets.append([])
            }
            buckets[bucket].append(item)
            bucketOfIndex[item.originalIndex] = bucket
        }
        positions = Array(repeating: 0, count: buckets.count)
        inFlight = Array(repeating: 0, count: buckets.count)
    }

    /// The next item to start, counted as in flight until `finished`; nil
    /// once every item has been handed out.
    mutating func next() -> HashBatchPlanner.Item? {
        var best: Int?
        for step in 1...max(1, buckets.count) {
            let bucket = (lastPicked + step) % buckets.count
            guard positions[bucket] < buckets[bucket].count else { continue }
            if best == nil || inFlight[bucket] < inFlight[best!] { best = bucket }
        }
        guard let bucket = best else { return nil }
        let item = buckets[bucket][positions[bucket]]
        positions[bucket] += 1
        inFlight[bucket] += 1
        lastPicked = bucket
        return item
    }

    /// Marks the item with `originalIndex` done, freeing its volume's slot.
    mutating func finished(originalIndex: Int) {
        guard let bucket = bucketOfIndex[originalIndex], inFlight[bucket] > 0 else { return }
        inFlight[bucket] -= 1
    }
}
