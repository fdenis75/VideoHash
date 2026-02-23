//
//  OSHashTests.swift
//  VideoHash
//
//  Created by Claude Code on 04/01/2026.
//

import Testing
import Foundation
@testable import VideoHash

@Suite("OSHash Generation Tests")
struct OSHashTests {
    let generator = OSHashGenerator()

    @Test("OSHash format is 16 hex characters")
    func testHashFormat() async throws {
        // Create a temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_video_\(UUID().uuidString).bin")
        
        // Create file with 128KB of data (minimum size)
        let data = Data(repeating: 0x42, count: 131072) // 128KB
        try data.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // Generate hash
        let hash = try await generator.generateHash(for: testFile)

        // Verify format
        #expect(hash.count == 16, "Hash should be 16 characters")

        // Verify all characters are hex
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        for char in hash {
            #expect(hexCharacters.contains(char.unicodeScalars.first!), "Hash should only contain hex characters")
        }
    }

    @Test("OSHash is deterministic")
    func testDeterministic() async throws {
        // Create a temporary test file
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_video_\(UUID().uuidString).bin")

        // Create file with specific data
        var data = Data()
        for i in 0..<(131072 / 8) { // 128KB of UInt64 values
            var value = UInt64(i)
            data.append(Data(bytes: &value, count: 8))
        }
        try data.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        // Generate hash multiple times
        let hash1 = try await generator.generateHash(for: testFile)
        let hash2 = try await generator.generateHash(for: testFile)
        let hash3 = try await generator.generateHash(for: testFile)

        // All hashes should be identical
        #expect(hash1 == hash2, "Hash should be deterministic")
        #expect(hash2 == hash3, "Hash should be deterministic")
    }

    @Test("OSHash different for different files")
    func testDifferentFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory

        // Create first file
        let testFile1 = tempDir.appendingPathComponent("test_video_1_\(UUID().uuidString).bin")
        let data1 = Data(repeating: 0x42, count: 131072)
        try data1.write(to: testFile1)

        // Create second file with different data
        let testFile2 = tempDir.appendingPathComponent("test_video_2_\(UUID().uuidString).bin")
        let data2 = Data(repeating: 0x99, count: 131072)
        try data2.write(to: testFile2)

        defer {
            try? FileManager.default.removeItem(at: testFile1)
            try? FileManager.default.removeItem(at: testFile2)
        }

        // Generate hashes
        let hash1 = try await generator.generateHash(for: testFile1)
        let hash2 = try await generator.generateHash(for: testFile2)

        // Hashes should be different
        #expect(hash1 != hash2, "Different files should have different hashes")
    }

    @Test("OSHash throws for non-existent file")
    func testNonExistentFile() async {
        let nonExistentFile = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).bin")

        await #expect(throws: HashError.self) {
            try await generator.generateHash(for: nonExistentFile)
        }
    }

    @Test("OSHash throws for file too small")
    func testFileTooSmall() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test_small_\(UUID().uuidString).bin")

        // Create file smaller than 128KB
        let data = Data(repeating: 0x42, count: 1024) // 1KB
        try data.write(to: testFile)

        defer {
            try? FileManager.default.removeItem(at: testFile)
        }

        await #expect(throws: HashError.self) {
            try await generator.generateHash(for: testFile)
        }
    }

    @Test("OSHash incorporates file size")
    func testIncorporatesFileSize() async throws {
        let tempDir = FileManager.default.temporaryDirectory

        // Create file with same content but different size
        let testFile1 = tempDir.appendingPathComponent("test_size_1_\(UUID().uuidString).bin")
        let data1 = Data(repeating: 0x42, count: 131072) // 128KB
        try data1.write(to: testFile1)

        let testFile2 = tempDir.appendingPathComponent("test_size_2_\(UUID().uuidString).bin")
        let data2 = Data(repeating: 0x42, count: 196608) // 192KB
        try data2.write(to: testFile2)

        defer {
            try? FileManager.default.removeItem(at: testFile1)
            try? FileManager.default.removeItem(at: testFile2)
        }

        // Generate hashes
        let hash1 = try await generator.generateHash(for: testFile1)
        let hash2 = try await generator.generateHash(for: testFile2)

        // Hashes should be different due to file size
        #expect(hash1 != hash2, "Files with different sizes should have different hashes")
    }
}
