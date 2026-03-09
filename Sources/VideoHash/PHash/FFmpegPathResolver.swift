//
//  FFmpegPathResolver.swift
//  VideoHash
//
//  Created by Codex on 09/03/2026.
//

import Foundation

/// Resolves the ffmpeg executable path for the current process.
struct FFmpegPathResolver: Sendable {
    private let environment: [String: String]
    private let bundledExecutablePath: @Sendable (String) -> String?
    private let isExecutableFile: @Sendable (String) -> Bool
    private let commonPaths: [String]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledExecutablePath: @escaping @Sendable (String) -> String? = {
            executableName in Self.defaultBundledExecutablePath(named: executableName)
        },
        isExecutableFile: @escaping @Sendable (String) -> Bool = {
            path in FileManager.default.isExecutableFile(atPath: path)
        },
        commonPaths: [String] = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/bin/ffmpeg"
        ]
    ) {
        self.environment = environment
        self.bundledExecutablePath = bundledExecutablePath
        self.isExecutableFile = isExecutableFile
        self.commonPaths = commonPaths
    }

    func resolve(configuredPath: String?) throws -> String {
        if let configuredPath {
            return try resolveConfiguredPath(configuredPath)
        }

        if let bundledPath = resolveBundledExecutable(named: "ffmpeg") {
            return bundledPath
        }

        if let pathResolvedExecutable = resolveExecutableOnPath(named: "ffmpeg") {
            return pathResolvedExecutable
        }

        if let commonPathExecutable = commonPaths.first(where: isExecutableFile) {
            return commonPathExecutable
        }

        throw HashError.frameExtractionFailed(
            reason: """
            ffmpeg executable not found. Install ffmpeg, set HashConfiguration.ffmpegPath, or in a sandboxed app bundle ffmpeg and point ffmpegPath to Bundle.main.path(forAuxiliaryExecutable: "ffmpeg")
            """
        )
    }

    private func resolveConfiguredPath(_ configuredPath: String) throws -> String {
        if configuredPath.contains("/") {
            guard isExecutableFile(configuredPath) else {
                throw HashError.frameExtractionFailed(
                    reason: "Configured ffmpegPath is not executable: \(configuredPath)"
                )
            }
            return configuredPath
        }

        if let bundledPath = resolveBundledExecutable(named: configuredPath) {
            return bundledPath
        }

        if let pathResolvedExecutable = resolveExecutableOnPath(named: configuredPath) {
            return pathResolvedExecutable
        }

        if let commonPathExecutable = commonPaths.first(
            where: { $0.hasSuffix("/\(configuredPath)") && isExecutableFile($0) }
        ) {
            return commonPathExecutable
        }

        throw HashError.frameExtractionFailed(
            reason: "Could not resolve ffmpeg executable named: \(configuredPath)"
        )
    }

    private func resolveBundledExecutable(named executableName: String) -> String? {
        guard let bundledPath = bundledExecutablePath(executableName),
              isExecutableFile(bundledPath) else {
            return nil
        }
        return bundledPath
    }

    private func resolveExecutableOnPath(named executableName: String) -> String? {
        guard let pathEnvironment = environment["PATH"] else {
            return nil
        }

        for directory in pathEnvironment.split(separator: ":") {
            let candidate = String(directory) + "/" + executableName
            if isExecutableFile(candidate) {
                return candidate
            }
        }

        return nil
    }

    private static func defaultBundledExecutablePath(named executableName: String) -> String? {
        let bundles = uniqueBundles([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)

        for bundle in bundles {
            if let auxiliaryExecutablePath = bundle.path(forAuxiliaryExecutable: executableName) {
                return auxiliaryExecutablePath
            }
        }

        for bundle in bundles {
            for candidatePath in fallbackBundleExecutablePaths(
                in: bundle,
                executableName: executableName
            ) where FileManager.default.isExecutableFile(atPath: candidatePath) {
                return candidatePath
            }
        }

        return nil
    }

    private static func uniqueBundles(_ bundles: [Bundle]) -> [Bundle] {
        var seenBundlePaths = Set<String>()
        return bundles.filter { bundle in
            seenBundlePaths.insert(bundle.bundlePath).inserted
        }
    }

    private static func fallbackBundleExecutablePaths(
        in bundle: Bundle,
        executableName: String
    ) -> [String] {
        [
            bundle.bundleURL.appendingPathComponent("Contents/Helpers/\(executableName)").path,
            bundle.bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)").path,
            bundle.bundleURL.appendingPathComponent("Contents/Resources/\(executableName)").path,
            bundle.sharedSupportURL?.appendingPathComponent(executableName).path,
            bundle.resourceURL?.appendingPathComponent(executableName).path
        ].compactMap { $0 }
    }
}
