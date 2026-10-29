import XCTest
@testable import NashiCore

final class MediaAudioCompatibilityTests: XCTestCase {
    func testMonoVorbisKeepsSampleRateAndContentWhenManagedBitrateIsUnsupported() throws {
        let directory = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for sampleRate in [48000, 44100, 22050, 16000] {
            let input = try tone(directory, sampleRate: sampleRate)
            let original = try Data(contentsOf: input)
            for bitrate in [128, 256, 320] {
                var options = OperationOptions(); options.audioBitrate = bitrate
                let output = try converted(input, format: "ogg", options: options)
                let info = try MediaEngine.inspect(output)
                XCTAssertEqual(info.audio?.codec, "vorbis")
                XCTAssertEqual(info.audio?.sampleRate, sampleRate)
                XCTAssertEqual(info.audio?.channels, 1)
                XCTAssertEqual(info.duration, 1, accuracy: 0.08)
                try assertAudibleTone(output)
                if sampleRate >= 44100, bitrate == 128 { XCTAssertEqual(info.audio?.bitRate, 128000) }
                else { XCTAssertNotEqual(info.audio?.bitRate, bitrate * 1000, "This input requires quality VBR, not a guaranteed managed bitrate.") }
            }
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix(".nashi-") })
    }

    func testMonoLossyProfilesPreserveSupportedRatesAndApplyCodecBitrateLimits() throws {
        let directory = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for sampleRate in [44100, 22050, 16000, 8000] {
            let input = try tone(directory, sampleRate: sampleRate)
            for format in ["mp3", "m4a", "opus", "wma"] {
                for bitrate in [256, 320] {
                    var options = OperationOptions(); options.audioBitrate = bitrate
                    let output = try converted(input, format: format, options: options)
                    let info = try MediaEngine.inspect(output)
                    XCTAssertEqual(info.audio?.channels, 1, "\(format) \(sampleRate) \(bitrate)")
                    XCTAssertEqual(info.audio?.sampleRate, format == "opus" ? 48000 : sampleRate)
                    XCTAssertEqual(info.duration, 1, accuracy: 0.16)
                    try assertAudibleTone(output)
                    if format == "mp3" {
                        let cap = sampleRate <= 12000 ? 64000 : sampleRate < 32000 ? 160000 : 320000
                        XCTAssertEqual(info.audio?.bitRate, min(bitrate * 1000, cap))
                    }
                    if format == "wma" { XCTAssertEqual(info.audio?.bitRate, bitrate * 1000) }
                    if format == "opus", sampleRate == 16000 || sampleRate == 8000 {
                        // Ogg Opus always advertises a 48kHz decoder clock; OpusHead retains
                        // the original encoder input rate when libopus supports that rate.
                        let data = try Data(contentsOf: output)
                        let header = try XCTUnwrap(data.range(of: Data("OpusHead".utf8)))
                        let offset = header.lowerBound + 12
                        let originalRate = data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
                        XCTAssertEqual(originalRate, UInt32(sampleRate))
                    }
                }
            }
        }
    }

    func testVorbisFallbackAlsoAppliesToTrimAndMonoChannelExports() throws {
        let directory = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try tone(directory, sampleRate: 16000, channels: 2)
        let ogg = try converted(input, format: "ogg", options: .init())
        var options = OperationOptions(); options.channels = 1
        let mono = try XCTUnwrap(MediaEngine.tool(.audioChannels, inputs: [ogg], options: options, token: .init()).first)
        XCTAssertEqual(try MediaEngine.inspect(mono).audio?.channels, 1)
        XCTAssertEqual(try MediaEngine.inspect(mono).audio?.sampleRate, 16000)
        try assertAudibleTone(mono)
        options.start = 0.1; options.end = 0.8
        let trimmed = try XCTUnwrap(MediaEngine.tool(.trimAudio, inputs: [mono], options: options, token: .init()).first)
        XCTAssertEqual(try MediaEngine.inspect(trimmed).duration, 0.7, accuracy: 0.08)
        XCTAssertEqual(try MediaEngine.inspect(trimmed).audio?.sampleRate, 16000)
        try assertAudibleTone(trimmed)
    }

    func testMonoVideoAudioUsesTheSameOpusLimit() throws {
        let directory = try OutputFiles.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = try tone(directory, sampleRate: 16000)
        let video = directory.appendingPathComponent("Mono video.mp4")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=96x64:rate=12:duration=1", "-i", input.path, "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-c:a", "aac", video.path])
        var options = OperationOptions(); options.audioBitrate = 320
        let webm = try converted(video, format: "webm", options: options)
        let info = try MediaEngine.inspect(webm)
        XCTAssertEqual(info.audio?.codec, "opus"); XCTAssertEqual(info.audio?.channels, 1)
        XCTAssertEqual(info.duration, 1, accuracy: 0.12)
        try assertAudibleTone(webm)
    }

    private func tone(_ directory: URL, sampleRate: Int, channels: Int = 1) throws -> URL {
        let output = directory.appendingPathComponent("Tone \(sampleRate) \(channels).wav")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=\(sampleRate):duration=1", "-ac", String(channels), "-c:a", "pcm_s16le", output.path])
        return output
    }

    private func converted(_ input: URL, format: String, options: OperationOptions) throws -> URL {
        try XCTUnwrap(MediaEngine.convert(input, to: format, options: options, token: .init()).first)
    }

    private func assertAudibleTone(_ input: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-ss", "0.2", "-i", input.path, "-t", "0.4", "-map", "0:a:0", "-ac", "1", "-ar", "48000", "-f", "f32le", "-"]).output
        let samples = data.withUnsafeBytes { bytes in stride(from: 0, to: bytes.count - 3, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float.self) } }
        XCTAssertFalse(samples.isEmpty, file: file, line: line)
        guard samples.count > 1 else { return }
        let rms = sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count))
        XCTAssertGreaterThan(rms, 0.04, file: file, line: line)
        let crossings = zip(samples, samples.dropFirst()).filter { ($0.0 >= 0) != ($0.1 >= 0) }.count
        let frequency = Double(crossings) / (2 * Double(samples.count) / 48000)
        XCTAssertEqual(frequency, 440, accuracy: 12, file: file, line: line)
    }
}
