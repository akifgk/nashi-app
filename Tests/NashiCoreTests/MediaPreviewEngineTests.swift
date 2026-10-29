import XCTest
import AVFoundation
@testable import NashiCore

final class MediaPreviewEngineTests: XCTestCase {
    private struct Fixtures {
        let directory: URL
        let video: URL
        let audio: URL
        init() throws {
            directory = try OutputFiles.temporaryDirectory()
            video = directory.appendingPathComponent("Original 'video'.mp4")
            audio = directory.appendingPathComponent("Envelope.wav")
            try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-nostdin", "-f", "lavfi", "-i", "testsrc2=size=128x96:rate=12:duration=2", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2", "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", video.path])
            let envelope = "aevalsrc=exprs='if(lt(t,0.5),0,if(lt(t,1),0.1*sin(2*PI*220*t),if(lt(t,1.5),0.8*sin(2*PI*220*t),0)))':s=48000:d=2"
            try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-nostdin", "-f", "lavfi", "-i", envelope, "-c:a", "pcm_s16le", audio.path])
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    func testNativeMediaUsesTheOriginalWithoutAWorkingCopy() async throws {
        let f = try Fixtures(); defer { f.remove() }
        for input in [f.video, f.audio] {
            let before = try Data(contentsOf: input)
            let preview = try await MediaPreviewEngine.prepare(input)
            XCTAssertEqual(preview.originalURL, input)
            XCTAssertEqual(preview.playbackURL, input)
            XCTAssertFalse(preview.isProxy)
            XCTAssertNil(preview.ownedTemporaryDirectory)
            preview.removeTemporaryFiles()
            XCTAssertEqual(try Data(contentsOf: input), before)
        }
    }

    func testUnsupportedVideoContainersProduceAVFoundationPlayableProxies() async throws {
        let f = try Fixtures(); defer { f.remove() }
        for format in ["mkv", "avi", "wmv", "webm"] {
            let inputs = try MediaEngine.convert(f.video, to: format, options: .init(), token: .init())
            let input = try XCTUnwrap(inputs.first)
            let source = try Data(contentsOf: input)
            let preview = try await MediaPreviewEngine.prepare(input)
            defer { preview.removeTemporaryFiles() }
            let native = (try? await AVURLAsset(url: input).load(.isPlayable)) ?? false
            if !native { XCTAssertTrue(preview.isProxy, format) }
            let playable = try await AVURLAsset(url: preview.playbackURL).load(.isPlayable)
            XCTAssertTrue(playable, format)
            let info = try MediaEngine.inspect(preview.playbackURL)
            XCTAssertTrue(info.hasAudio, format); XCTAssertTrue(info.hasVideo, format)
            XCTAssertEqual(info.video?.width, 128, format); XCTAssertEqual(info.video?.height, 96, format)
            XCTAssertEqual(info.duration, 2, accuracy: 0.2, format)
            XCTAssertEqual(try Data(contentsOf: input), source, format)
            if preview.isProxy {
                XCTAssertNotEqual(preview.playbackURL.deletingLastPathComponent(), input.deletingLastPathComponent())
                XCTAssertEqual(info.video?.codec, "h264", format)
                XCTAssertEqual(info.audio?.codec, "aac", format)
            }
        }
    }

    func testUnsupportedAudioContainersProducePlayableAudioPreviews() async throws {
        let f = try Fixtures(); defer { f.remove() }
        for format in ["ogg", "opus", "wma"] {
            let outputs = try MediaEngine.convert(f.audio, to: format, options: .init(), token: .init())
            let input = try XCTUnwrap(outputs.first)
            let preview = try await MediaPreviewEngine.prepare(input)
            defer { preview.removeTemporaryFiles() }
            let playable = try await AVURLAsset(url: preview.playbackURL).load(.isPlayable)
            XCTAssertTrue(playable, format)
            let info = try MediaEngine.inspect(preview.playbackURL)
            XCTAssertTrue(info.hasAudio, format); XCTAssertFalse(info.hasVideo, format)
            XCTAssertEqual(info.duration, 2, accuracy: 0.2, format)
            if preview.isProxy { XCTAssertEqual(info.audio?.codec, "aac", format) }
            let peaks = try MediaPreviewEngine.waveformPeaks(preview.playbackURL, bins: 40)
            XCTAssertGreaterThan(peaks.max() ?? 0, 0.5, format)
        }
    }

    func testProxyPreservesRotatedDisplayGeometryAndDuration() async throws {
        let f = try Fixtures(); defer { f.remove() }
        let rotated = f.directory.appendingPathComponent("Rotated.mp4")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-display_rotation", "90", "-i", f.video.path, "-map", "0", "-c", "copy", rotated.path])
        let source = try Data(contentsOf: rotated)
        let preview = try await MediaPreviewEngine.prepare(rotated, forceProxy: true)
        defer { preview.removeTemporaryFiles() }
        XCTAssertTrue(preview.isProxy)
        let info = try MediaEngine.inspect(preview.playbackURL)
        XCTAssertEqual(info.video?.width, 96); XCTAssertEqual(info.video?.height, 128)
        XCTAssertEqual(info.video?.rotation, 0)
        XCTAssertEqual(info.duration, 2, accuracy: 0.1)
        XCTAssertEqual(try Data(contentsOf: rotated), source)
        let playable = try await AVURLAsset(url: preview.playbackURL).load(.isPlayable)
        XCTAssertTrue(playable)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: preview.playbackURL))
        generator.appliesPreferredTrackTransform = true
        let image = try generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
        XCTAssertEqual(image.width, 96); XCTAssertEqual(image.height, 128)
        let directory = try XCTUnwrap(preview.ownedTemporaryDirectory)
        preview.removeTemporaryFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotated.path))
    }

    func testWaveformRetainsSilenceAndDifferentPeakLevels() throws {
        let f = try Fixtures(); defer { f.remove() }
        let peaks = try MediaPreviewEngine.waveformPeaks(f.audio, bins: 200)
        XCTAssertEqual(peaks.count, 200)
        XCTAssertTrue(peaks.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        XCTAssertLessThan(peaks[10..<40].max() ?? 1, 0.0001)
        XCTAssertEqual(peaks[60..<90].max() ?? 0, 0.1, accuracy: 0.003)
        XCTAssertEqual(peaks[110..<140].max() ?? 0, 0.8, accuracy: 0.003)
        XCTAssertLessThan(peaks[160..<190].max() ?? 1, 0.0001)
    }

    func testWaveformKeepsOppositePhaseChannelsAndCoarseLongFileBins() throws {
        let f = try Fixtures(); defer { f.remove() }
        let opposite = f.directory.appendingPathComponent("Opposite phase.wav")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-f", "lavfi", "-i", "aevalsrc=exprs='0.5*sin(2*PI*440*t)|-0.5*sin(2*PI*440*t)':s=48000:d=1", opposite.path])
        let peaks = try MediaPreviewEngine.waveformPeaks(opposite, bins: 80)
        XCTAssertEqual(peaks.count, 80)
        XCTAssertGreaterThan(peaks.min() ?? 0, 0.49, "Measuring channel peaks must not cancel opposite-phase audio.")
        let long = f.directory.appendingPathComponent("Long silent.flac")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", "120", "-c:a", "flac", long.path])
        let coarse = try MediaPreviewEngine.waveformPeaks(long, bins: 37)
        XCTAssertEqual(coarse.count, 37)
        XCTAssertTrue(coarse.allSatisfy { $0 == 0 })
    }

    func testBleepPreviewIsPlayableChangesOnlyTheRangeAndOwnsAllWorkingFiles() async throws {
        let f = try Fixtures(); defer { f.remove() }
        let before = try Data(contentsOf: f.audio)
        let siblingNames = try FileManager.default.contentsOfDirectory(atPath: f.directory.path).sorted()
        var options = OperationOptions()
        options.audioRedactions = [TimeRange(start: 0.6, end: 0.8)]
        options.outputDirectory = f.directory // A preview must override an export destination.
        let preview = try await MediaPreviewEngine.bleepPreview(f.audio, options: options)
        defer { preview.removeTemporaryFiles() }
        XCTAssertTrue(preview.isProxy)
        let playable = try await AVURLAsset(url: preview.playbackURL).load(.isPlayable)
        XCTAssertTrue(playable)
        let tone = try samples(preview.playbackURL, start: 0.65, duration: 0.1)
        let crossings = zip(tone, tone.dropFirst()).filter { ($0.0 < 0) != ($0.1 < 0) }.count
        XCTAssertEqual(Double(crossings) / 0.2, 1000, accuracy: 15)
        XCTAssertEqual(try samples(preview.playbackURL, start: 0.85, duration: 0.1), try samples(f.audio, start: 0.85, duration: 0.1))
        XCTAssertEqual(try Data(contentsOf: f.audio), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).sorted(), siblingNames)
        let directory = try XCTUnwrap(preview.ownedTemporaryDirectory)
        preview.removeTemporaryFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testChannelWaveformsMeasureTheSelectedChannel() throws {
        let f=try Fixtures();defer{f.remove()}
        let stereo=f.directory.appendingPathComponent("Different levels.wav")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"),["-v","error","-f","lavfi","-i","aevalsrc=exprs='0.2*sin(2*PI*440*t)|0.8*sin(2*PI*880*t)':s=48000:d=1",stereo.path])
        let before=try Data(contentsOf:stereo)
        let left=try MediaPreviewEngine.waveformPeaks(stereo,bins:50,channel:0),right=try MediaPreviewEngine.waveformPeaks(stereo,bins:50,channel:1)
        XCTAssertEqual(left.max() ?? 0,0.2,accuracy:0.001);XCTAssertEqual(right.max() ?? 0,0.8,accuracy:0.001)
        XCTAssertThrowsError(try MediaPreviewEngine.waveformPeaks(stereo,channel:2))
        XCTAssertThrowsError(try MediaPreviewEngine.waveformPeaks(stereo,channel:-1))
        XCTAssertEqual(try Data(contentsOf:stereo),before)
    }

    func testVisualizationPreviewIsBoundedPlayableAndOwnsItsTemporaryFiles() async throws {
        let f=try Fixtures();defer{f.remove()}
        let still=f.directory.appendingPathComponent("Still.png")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"),["-v","error","-i",f.video.path,"-frames:v","1",still.path])
        let original=try Data(contentsOf:f.audio),siblings=try FileManager.default.contentsOfDirectory(atPath:f.directory.path).sorted()
        for style in ["waveform","spectrum","bars","image"] {
            var options=OperationOptions();options.width=1080;options.height=1920;options.visualizationStyle=style;options.visualizationImage=still;options.outputDirectory=f.directory
            let preview=try await MediaPreviewEngine.visualizationPreview(f.audio,options:options,maximumDuration:0.4)
            let info=try MediaEngine.inspect(preview.playbackURL)
            XCTAssertTrue(info.hasAudio);XCTAssertTrue(info.hasVideo)
            XCTAssertEqual(info.video?.width,360);XCTAssertEqual(info.video?.height,640)
            XCTAssertEqual(info.duration,0.4,accuracy:0.15)
            let playable=try await AVURLAsset(url:preview.playbackURL).load(.isPlayable);XCTAssertTrue(playable)
            XCTAssertEqual(try Data(contentsOf:f.audio),original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:f.directory.path).sorted(),siblings)
            let folder=try XCTUnwrap(preview.ownedTemporaryDirectory);preview.removeTemporaryFiles()
            XCTAssertFalse(FileManager.default.fileExists(atPath:folder.path))
        }
        let token=CancellationToken();token.cancel()
        do { _=try await MediaPreviewEngine.visualizationPreview(f.audio,token:token);XCTFail("Expected cancellation") }
        catch { guard case NashiError.cancelled=error else { return XCTFail("Unexpected error: \(error)") } }
    }

    func testValidationAndCancellationDoNotModifyTheSource() async throws {
        let f = try Fixtures(); defer { f.remove() }
        XCTAssertThrowsError(try MediaPreviewEngine.waveformPeaks(f.audio, bins: 0))
        XCTAssertThrowsError(try MediaPreviewEngine.waveformPeaks(f.audio, bins: 10001))
        let token = CancellationToken(); token.cancel()
        XCTAssertThrowsError(try MediaPreviewEngine.waveformPeaks(f.audio, token: token))
        do { _ = try await MediaPreviewEngine.prepare(f.video, token: token); XCTFail("Expected cancellation.") }
        catch { guard case NashiError.cancelled = error else { return XCTFail("Unexpected error: \(error)") } }
        let empty = f.directory.appendingPathComponent("Invalid.mkv")
        try Data("Invalid media".utf8).write(to: empty)
        do { _ = try await MediaPreviewEngine.prepare(empty); XCTFail("Expected invalid media rejection.") }
        catch { XCTAssertTrue(FileManager.default.fileExists(atPath: empty.path)) }
    }

    private func samples(_ url: URL, start: Double, duration: Double) throws -> [Float] {
        let data = try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-ss", String(start), "-i", url.path, "-t", String(duration), "-map", "0:a:0", "-ac", "1", "-ar", "48000", "-f", "f32le", "-"]).output
        return data.withUnsafeBytes { bytes in stride(from: 0, to: bytes.count - 3, by: 4).map { bytes.loadUnaligned(fromByteOffset: $0, as: Float.self) } }
    }
}
