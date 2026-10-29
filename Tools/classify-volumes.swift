#!/usr/bin/env swift
// Standalone macOS utility. No package dependencies, benchmarks, or disk writes.
// swift Tools/classify-volumes.swift [--json] [--all | /path/to/volume ...]
// Estimates only: USB bridge metadata and negotiated link speed may be unavailable.
import Foundation
import Darwin

enum Category: String, Codable {
    case internalStorage = "internal"
    case fast = "ext-fast"
    case medium = "ext-med"
    case slow = "ext-slow"
}

struct Estimate: Codable {
    let path: String
    let name: String
    let category: Category
    let reason: String
    let devices: [String]
    let buses: [String]
    var readTest: ReadTest? = nil
}

struct UtilityError: Error, CustomStringConvertible {
    let description: String
}

/// Synchronous and read-only; drain stdout before waiting to avoid a full pipe.
func diskInfo(_ device: String) throws -> [String: Any] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    process.arguments = ["info", "-plist", device]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { throw UtilityError(description: "Cannot inspect \(device) with diskutil") }
    return info
}

/// Resolve APFS synthesized volumes to their backing stores, then whole disks.
func physicalDisks(_ info: [String: Any], visited: Set<String> = []) throws -> [[String: Any]] {
    let identifier = info["DeviceIdentifier"] as? String ?? ""
    guard !identifier.isEmpty, !visited.contains(identifier) else {
        throw UtilityError(description: "Cannot resolve physical storage for \(identifier)")
    }
    let visited = visited.union([identifier])
    if let stores = info["APFSPhysicalStores"] as? [[String: Any]], !stores.isEmpty {
        return try stores.flatMap { store in
            guard let device = store["APFSPhysicalStore"] as? String else {
                throw UtilityError(description: "Missing APFS physical store identifier")
            }
            return try physicalDisks(diskInfo(device), visited: visited)
        }
    }
    if let parent = info["ParentWholeDisk"] as? String, parent != identifier {
        return try physicalDisks(diskInfo(parent), visited: visited)
    }
    return [info]
}

func classify(_ disks: [[String: Any]]) -> (Category, String) {
    guard !disks.isEmpty else { return (.slow, "Unknown backing storage; conservative fallback") }
    let buses = disks.map { ($0["BusProtocol"] as? String ?? "unknown").lowercased() }
    if buses.contains(where: { $0.contains("disk image") || $0.contains("virtual") }) ||
        disks.contains(where: { ($0["VirtualOrPhysical"] as? String)?.lowercased() == "virtual" }) {
        return (.slow, "Virtual storage; backing hardware unknown")
    }
    if disks.allSatisfy({ $0["Internal"] as? Bool == true }) {
        return (.internalStorage, "All backing disks are internal (location category)")
    }
    // diskutil often reports only "USB", not its negotiated generation/speed.
    // Never infer USB 3+ from the connector, device name, or SSD status.
    if buses.contains(where: { $0.contains("usb 2") || $0.contains("usb 1") || $0.contains("firewire") }) {
        return (.slow, "Legacy external connection")
    }
    guard disks.allSatisfy({ $0["Internal"] as? Bool == false }) else {
        return (.slow, "Unknown or mixed internal/external backing storage")
    }
    if disks.allSatisfy({ $0["SolidState"] as? Bool == true }) {
        return (.fast, "External SSD; connection speed unverified")
    }
    if disks.allSatisfy({ $0["SolidState"] as? Bool != nil }),
       disks.contains(where: { $0["SolidState"] as? Bool == false }) {
        return (.medium, "External rotational storage; connection speed unverified")
    }
    return (.slow, "Media type unavailable; conservative fallback")
}

func estimate(_ url: URL) throws -> Estimate {
    let values = try url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeNameKey, .volumeURLKey])
    let volume = values.volume ?? url
    if values.volumeIsLocal == false {
        return Estimate(path: volume.path, name: values.volumeName ?? volume.lastPathComponent,
                        category: .slow, reason: "Network volume; conservative fallback, not measured",
                        devices: [], buses: ["network"])
    }
    let info = try diskInfo(volume.path)
    let disks: [[String: Any]]
    do {
        disks = try physicalDisks(info)
    } catch {
        return Estimate(path: volume.path, name: values.volumeName ?? volume.lastPathComponent,
                        category: .slow, reason: "Backing storage unresolved: \(error)", devices: [], buses: [])
    }
    let (category, reason) = classify(disks)
    return Estimate(path: volume.path, name: values.volumeName ?? volume.lastPathComponent,
                    category: category, reason: reason,
                    devices: Array(Set(disks.compactMap { $0["DeviceIdentifier"] as? String })).sorted(),
                    buses: Array(Set(disks.compactMap { $0["BusProtocol"] as? String })).sorted())
}

struct ReadTest: Codable {
    let megabytesPerSecond: Double?
    let seconds: Double
    let bytes: Int64
    let category: Category?
    let note: String
}

/// Policy thresholds for sequential reads, in decimal MB/s; not random-I/O ratings.
func readCategory(_ speed: Double, internalStorage: Bool) -> Category {
    if internalStorage { return .internalStorage }
    if speed >= 300 { return .fast }
    if speed >= 80 { return .medium }
    return .slow
}

/// Find ordinary, allocated local files without crossing into other volumes.
/// Discovery is bounded separately from the five-second timed read phase.
func sampleFiles(_ root: URL) -> [URL] {
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey,
        .fileSizeKey, .fileAllocatedSizeKey, .isUbiquitousItemKey]
    var rootStat = stat()
    guard stat(root.path, &rootStat) == 0 else { return [] }
    func usable(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(forKeys: keys),
              v.isRegularFile == true, v.isSymbolicLink != true,
              v.isUbiquitousItem != true,
              let size = v.fileSize, size >= 16 * 1024 * 1024,
              let allocated = v.fileAllocatedSize, allocated >= size else { return false }
        return true
    }
    if usable(root) { return [root] }
    guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in true }
    ) else { return [] }
    let start = ContinuousClock.now
    var files: [URL] = []
    var count = 0
    for case let url as URL in enumerator {
        count += 1
        if start.duration(to: .now) >= .seconds(3) || count > 20_000 { break }
        var itemStat = stat()
        // lstat avoids following symlinks to another drive or cloud location.
        guard lstat(url.path, &itemStat) == 0,
              itemStat.st_dev == rootStat.st_dev else {
            enumerator.skipDescendants()
            continue
        }
        if (itemStat.st_mode & S_IFMT) == S_IFLNK {
            enumerator.skipDescendants()
            continue
        }
        if usable(url) { files.append(url) }
        if files.count >= 32 { break }
    }
    return files
}

func benchmark(_ roots: [URL], internalStorage: Bool) -> ReadTest {
    let files = roots.lazy.map(sampleFiles).first(where: { !$0.isEmpty }) ?? []
    guard !files.isEmpty else {
        return ReadTest(megabytesPerSecond: nil, seconds: 0, bytes: 0, category: nil,
                        note: "No readable allocated file >=16 MiB found; pass a large file explicitly")
    }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: 4 * 1024 * 1024, alignment: 4096)
    defer { buffer.deallocate() }
    let clock = ContinuousClock()
    let start = clock.now
    var bytes: Int64 = 0
    var failures = 0
    // Read each byte at most once; never loop over a tiny file to inflate the score.
    for file in files {
        if start.duration(to: clock.now) >= .seconds(5) { break }
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { failures += 1; continue }
        defer { close(fd) }
        var metadata = stat()
        guard fstat(fd, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
              fcntl(fd, F_NOCACHE, 1) == 0 else { failures += 1; continue }
        while start.duration(to: clock.now) < .seconds(5) {
            let amount = read(fd, buffer, 4 * 1024 * 1024)
            if amount < 0 && errno == EINTR { continue }
            if amount <= 0 {
                if amount < 0 { failures += 1 }
                break
            }
            bytes += Int64(amount)
        }
    }
    let duration = start.duration(to: clock.now).components
    let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    guard bytes > 0, seconds > 0 else {
        return ReadTest(megabytesPerSecond: nil, seconds: seconds, bytes: bytes, category: nil,
                        note: "Read failed or F_NOCACHE unsupported")
    }
    let speed = Double(bytes) / seconds / 1_000_000
    let complete = seconds >= 5
    return ReadTest(megabytesPerSecond: speed, seconds: seconds, bytes: bytes,
                    category: complete ? readCategory(speed, internalStorage: internalStorage) : nil,
                    note: "Sequential read, F_NOCACHE; " +
                        (complete ? "five-second sample" : "sample exhausted before five seconds; no measured category") +
                        (failures > 0 ? "; some files unreadable" : "") +
                        "; device/OS caches and current load can affect results")
}

func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.contains("--help") {
        print("""
        Usage: swift Tools/classify-volumes.swift [--json] [--read-test] [--all | PATH ...]
        No paths: list visible mounted volumes. --all includes hidden volumes.
        PATH may be a volume, folder, or file. --json produces a JSON array.
        Estimates: internal hardware -> internal; external SSD -> ext-fast;
        external HDD -> ext-med; network/virtual/unknown -> ext-slow.
        USB link speed is usually unavailable: an SSD on USB 2 can be overrated.
        --read-test: five seconds of sequential reads per backing drive (no writes).
        Discovery takes up to three seconds per search root; individual I/O may overrun.
        External measured categories: >=300 MB/s fast, >=80 medium, otherwise slow.
        Network and virtual storage are skipped. Shared backing disks are tested once.
        Default mode reads metadata only. Internal remains a location category.
        """)
        return
    }
    let allowed = ["--json", "--all", "--read-test"]
    if let unknown = arguments.first(where: { $0.hasPrefix("-") && !allowed.contains($0) }) {
        throw UtilityError(description: "Unknown option: \(unknown)")
    }
    let paths = arguments.filter { !allowed.contains($0) }
    guard paths.isEmpty || !arguments.contains("--all") else {
        throw UtilityError(description: "Use --all or explicit paths, not both")
    }
    let urls: [URL]
    if paths.isEmpty {
        guard let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: arguments.contains("--all") ? [] : [.skipHiddenVolumes]
        ) else { throw UtilityError(description: "Cannot enumerate mounted volumes") }
        urls = mounted
    } else {
        urls = paths.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath() }
    }
    var results: [Estimate] = []
    var inputsByDevice: [String: [URL]] = [:]
    var failed = false
    for url in urls.sorted(by: { $0.path < $1.path }) {
        do {
            let result = try estimate(url)
            inputsByDevice[result.devices.joined(separator: ","), default: []].append(url)
            if !results.contains(where: { $0.path == result.path }) { results.append(result) }
        } catch {
            failed = true
            FileHandle.standardError.write(Data("\(url.path): \(error)\n".utf8))
        }
    }
    if arguments.contains("--read-test") {
        var tests: [String: ReadTest] = [:]
        for index in results.indices {
            let result = results[index]
            guard !result.devices.isEmpty,
                  !result.buses.contains(where: { $0.lowercased().contains("disk image") }),
                  !result.reason.contains("Virtual storage") else { continue }
            let key = result.devices.joined(separator: ",")
            if tests[key] == nil {
                FileHandle.standardError.write(Data("Read test: \(result.path) (\(key))…\n".utf8))
                // Prefer caller-supplied files/folders; for /, look in the user's data volume.
                let supplied = inputsByDevice[key] ?? []
                let roots = supplied.flatMap { url -> [URL] in
                    url.path == "/" ? [FileManager.default.homeDirectoryForCurrentUser, url] : [url]
                }
                tests[key] = benchmark(roots, internalStorage: result.category == .internalStorage)
            }
            results[index].readTest = tests[key]
        }
    }
    if arguments.contains("--json") {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(results), as: UTF8.self))
    } else {
        for result in results {
            print("\(result.category.rawValue)\t\(result.path)")
            print("  \(result.reason) [\(result.buses.joined(separator: ", ")); \(result.devices.joined(separator: ", "))]")
            if let test = result.readTest {
                if let speed = test.megabytesPerSecond {
                    print("  Read: \(String(format: "%.1f", speed)) MB/s in \(String(format: "%.2f", test.seconds)) s → \(test.category?.rawValue ?? "incomplete")")
                }
                print("  \(test.note)")
            }
        }
    }
    if failed { exit(1) }
}

do { try run() } catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    exit(1)
}
