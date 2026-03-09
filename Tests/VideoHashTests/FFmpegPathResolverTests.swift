import Foundation
import Testing
@testable import VideoHash

@Suite("FFmpeg Path Resolver Tests")
struct FFmpegPathResolverTests {
    @Test("Resolver prefers bundled auxiliary executable before PATH and common locations")
    func prefersBundledExecutable() throws {
        let bundledPath = "/Applications/Test.app/Contents/MacOS/ffmpeg"
        let pathExecutable = "/usr/local/bin/ffmpeg"
        let commonExecutable = "/opt/homebrew/bin/ffmpeg"
        let executablePaths = Set([bundledPath, pathExecutable, commonExecutable])

        let resolver = FFmpegPathResolver(
            environment: ["PATH": "/usr/local/bin:/usr/bin"],
            bundledExecutablePath: { executableName in
                executableName == "ffmpeg" ? bundledPath : nil
            },
            isExecutableFile: { executablePaths.contains($0) },
            commonPaths: [commonExecutable]
        )

        let resolvedPath = try resolver.resolve(configuredPath: nil)

        #expect(resolvedPath == bundledPath)
    }

    @Test("Resolver can resolve a configured executable name from the app bundle")
    func resolvesConfiguredExecutableNameFromBundle() throws {
        let bundledPath = "/Applications/Test.app/Contents/Helpers/ffmpeg-custom"
        let executablePaths = Set([bundledPath])

        let resolver = FFmpegPathResolver(
            environment: [:],
            bundledExecutablePath: { executableName in
                executableName == "ffmpeg-custom" ? bundledPath : nil
            },
            isExecutableFile: { executablePaths.contains($0) },
            commonPaths: []
        )

        let resolvedPath = try resolver.resolve(configuredPath: "ffmpeg-custom")

        #expect(resolvedPath == bundledPath)
    }

    @Test("Resolver reports sandbox guidance when ffmpeg cannot be found")
    func reportsSandboxGuidanceWhenMissing() {
        let resolver = FFmpegPathResolver(
            environment: [:],
            bundledExecutablePath: { _ in nil },
            isExecutableFile: { _ in false },
            commonPaths: []
        )

        do {
            _ = try resolver.resolve(configuredPath: nil)
            Issue.record("Expected ffmpeg resolution to fail")
        } catch let error as HashError {
            guard case .frameExtractionFailed(let reason) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }

            #expect(reason.contains("Bundle.main.path(forAuxiliaryExecutable: \"ffmpeg\")"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
