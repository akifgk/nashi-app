import XCTest
@testable import NashiCore

final class MediaEngineTests: XCTestCase {
    private struct Fixtures {
        let directory: URL
        let video: URL
        let audio: URL
        let silent: URL
        init() throws {
            directory = try OutputFiles.temporaryDirectory()
            // Metacharacters in real filenames exercise argument handling without a shell.
            video = directory.appendingPathComponent("Clip 'quoted' $dollar.mp4")
            audio = directory.appendingPathComponent("Quiet tone.wav")
            silent = directory.appendingPathComponent("Silent portrait.mov")
            let executable = try Dependencies.executable("ffmpeg")
            try ProcessRunner.run(executable, ["-hide_banner", "-v", "error", "-nostdin", "-n", "-f", "lavfi", "-i", "testsrc2=size=128x96:rate=12:duration=3", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3", "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "12", "-pix_fmt", "yuv420p", "-c:a", "aac", "-metadata", "title=Private source title", "-metadata", "comment=Remove this comment", "-metadata:s:a:0", "language=eng", video.path])
            try ProcessRunner.run(executable, ["-hide_banner", "-v", "error", "-nostdin", "-n", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3", "-af", "volume=0.08", "-ac", "2", "-c:a", "pcm_s16le", "-metadata", "title=Quiet source", audio.path])
            try ProcessRunner.run(executable, ["-hide_banner", "-v", "error", "-nostdin", "-n", "-f", "lavfi", "-i", "color=c=blue:size=80x120:rate=12:duration=1", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p", silent.path])
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    func testEveryAudioFormatDecodesAndRoundTrips() throws {
        let f = try Fixtures(); defer { f.remove() }
        let original = try Data(contentsOf: f.audio)
        let expectedCodecs = ["mp3": "mp3", "m4a": "aac", "wav": "pcm_s16le", "flac": "flac", "ogg": "vorbis", "opus": "opus", "aiff": "pcm_s16be", "wma": "wmav2"]
        for format in expectedCodecs.keys.sorted() {
            let output = try XCTUnwrap(MediaEngine.convert(f.audio, to: format, options: .init(), token: .init()).first)
            XCTAssertNotEqual(output, f.audio)
            let info = try MediaEngine.inspect(output)
            XCTAssertEqual(info.audio?.codec, expectedCodecs[format], format)
            XCTAssertFalse(info.hasVideo, format)
            XCTAssertEqual(info.duration, 3, accuracy: 0.15, format)
            let decoded = try samples(output, start: 0.5, duration: 0.2)
            XCTAssertGreaterThan(rms(decoded), 0.001, format)
            let roundTrip = try XCTUnwrap(MediaEngine.convert(output, to: "wav", options: .init(), token: .init()).first)
            XCTAssertEqual(try MediaEngine.inspect(roundTrip).audio?.sampleRate, 48000, format)
        }
        XCTAssertEqual(try Data(contentsOf: f.audio), original)
    }

    func testEveryVideoFormatAndGIFAndAudioExtraction() throws {
        let f = try Fixtures(); defer { f.remove() }
        let original = try Data(contentsOf: f.video)
        let codecs = ["mp4": "h264", "mov": "h264", "mkv": "h264", "webm": "vp9", "avi": "mpeg4", "wmv": "wmv2", "gif": "gif"]
        for format in codecs.keys.sorted() {
            var options = OperationOptions(); options.width = 96
            let output = try XCTUnwrap(MediaEngine.convert(f.video, to: format, options: options, token: .init()).first)
            let info = try MediaEngine.inspect(output)
            XCTAssertEqual(info.video?.codec, codecs[format], format)
            XCTAssertEqual(info.video?.width, 96, format)
            XCTAssertEqual(info.video?.height, 72, format)
            XCTAssertEqual(info.hasAudio, format != "gif", format)
            XCTAssertEqual(info.duration, 3, accuracy: 0.25, format)
            XCTAssertEqual(try frame(output, time: 0.5).count, 96 * 72 * 3, format)
            let roundTrip = try XCTUnwrap(MediaEngine.convert(output, to: "mp4", options: .init(), token: .init()).first)
            XCTAssertEqual(try MediaEngine.inspect(roundTrip).video?.codec, "h264", format)
        }
        let mp3 = try XCTUnwrap(MediaEngine.convert(f.video, to: "mp3", options: .init(), token: .init()).first)
        XCTAssertFalse(try MediaEngine.inspect(mp3).hasVideo)
        XCTAssertGreaterThan(rms(try samples(mp3, start: 0.5, duration: 0.2)), 0.01)
        XCTAssertEqual(try Data(contentsOf: f.video), original)
    }

    func testTrimVideoAudioAndSilentEndTrimming() throws {
        let f = try Fixtures(); defer { f.remove() }
        var options = OperationOptions(); options.start = 0.5; options.end = 1.5
        let video = try output(.trimVideo, input: f.video, options: options)
        let audio = try output(.trimAudio, input: f.audio, options: options)
        XCTAssertEqual(try MediaEngine.inspect(video).duration, 1, accuracy: 0.1)
        XCTAssertEqual(try MediaEngine.inspect(audio).duration, 1, accuracy: 0.03)
        let padded = f.directory.appendingPathComponent("Padded.wav")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-i", f.audio.path, "-af", "adelay=500:all=1,apad=pad_dur=0.5", padded.path])
        options.start = 0; options.end = nil; options.trimSilence = true
        let trimmed = try output(.trimAudio, input: padded, options: options)
        XCTAssertEqual(try MediaEngine.inspect(trimmed).duration, 3, accuracy: 0.08)
    }

    func testMuteAndCropKeepTheExpectedTracks() throws {
        let f = try Fixtures(); defer { f.remove() }
        let muted = try output(.muteVideo, input: f.video)
        let mutedInfo = try MediaEngine.inspect(muted)
        XCTAssertTrue(mutedInfo.hasVideo); XCTAssertFalse(mutedInfo.hasAudio)
        XCTAssertEqual(mutedInfo.duration, 3, accuracy: 0.05)
        var options = OperationOptions(); options.crop = EditRect(x: 16, y: 8, width: 64, height: 48)
        let cropped = try output(.cropVideo, input: f.video, options: options)
        let cropInfo = try MediaEngine.inspect(cropped)
        XCTAssertEqual(cropInfo.video?.width, 64); XCTAssertEqual(cropInfo.video?.height, 48)
        XCTAssertEqual(cropInfo.audio?.codec, try MediaEngine.inspect(f.video).audio?.codec)
        XCTAssertEqual(cropInfo.duration, 3, accuracy: 0.1)
    }

    func testSpeedPreservesPitchAndSupportsSilentVideo() throws {
        let f = try Fixtures(); defer { f.remove() }
        for speed in [0.25, 0.5, 1.5, 2, 4] {
            var options = OperationOptions(); options.speed = speed
            let output = try self.output(.changeVideoSpeed, input: f.video, options: options)
            XCTAssertEqual(try MediaEngine.inspect(output).duration, 3 / speed, accuracy: 0.25)
            let decoded = try samples(output, start: 0.15, duration: 0.3)
            let frequency = Double(zeroCrossings(decoded)) / (2 * 0.3)
            XCTAssertEqual(frequency, 440, accuracy: 25, "Pitch should remain constant at \(speed)×")
        }
        var options = OperationOptions(); options.speed = 2
        let silent = try output(.changeVideoSpeed, input: f.silent, options: options)
        XCTAssertFalse(try MediaEngine.inspect(silent).hasAudio)
        XCTAssertEqual(try MediaEngine.inspect(silent).duration, 0.5, accuracy: 0.12)
    }

    func testJoinUsesFirstCanvasAndInsertsSilenceForSilentClips() throws {
        let f = try Fixtures(); defer { f.remove() }
        let joined = try XCTUnwrap(MediaEngine.tool(.joinVideos, inputs: [f.video, f.silent], options: .init(), token: .init()).first)
        let info = try MediaEngine.inspect(joined)
        XCTAssertEqual(info.video?.width, 128); XCTAssertEqual(info.video?.height, 96)
        XCTAssertEqual(info.duration, 4, accuracy: 0.15); XCTAssertTrue(info.hasAudio)
        XCTAssertGreaterThan(rms(try samples(joined, start: 0.5, duration: 0.2)), 0.01)
        XCTAssertLessThan(rms(try samples(joined, start: 3.5, duration: 0.2)), 0.0001)
        let pixels = try frame(joined, time: 3.5)
        let offset = (48 * 128 + 64) * 3
        XCTAssertLessThan(pixels[offset], 20); XCTAssertGreaterThan(pixels[offset + 2], 220)
        let reverse = try XCTUnwrap(MediaEngine.tool(.joinVideos, inputs: [f.silent, f.video], options: .init(), token: .init()).first)
        XCTAssertEqual(try MediaEngine.inspect(reverse).video?.width, 80)
        XCTAssertEqual(try MediaEngine.inspect(reverse).video?.height, 120)
    }

    func testSnapshotsAreFullResolutionAndSplitAtCustomAndEqualPoints() throws {
        let f = try Fixtures(); defer { f.remove() }
        let original=try Data(contentsOf:f.video)
        var options = OperationOptions(); options.snapshotTimes = [0, 1.5, 2.9]
        let images = try MediaEngine.tool(.videoSnapshots, inputs: [f.video], options: options, token: .init())
        XCTAssertEqual(images.count, 3)
        for image in images { let info = try MediaEngine.inspect(image); XCTAssertEqual(info.video?.width, 128); XCTAssertEqual(info.video?.height, 96) }
        options.splitPoints = [2.25, 0.75]
        let custom = try MediaEngine.tool(.splitVideo, inputs: [f.video], options: options, token: .init())
        XCTAssertEqual(custom.count, 3)
        XCTAssertEqual(Set(custom.map{$0.deletingLastPathComponent()}).count,1)
        XCTAssertNotEqual(custom[0].deletingLastPathComponent(),f.video.deletingLastPathComponent())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:custom[0].deletingLastPathComponent().path).count,3)
        for (index, duration) in [0.75, 1.5, 0.75].enumerated() { XCTAssertEqual(try MediaEngine.inspect(custom[index]).duration, duration, accuracy: 0.15) }
        options.splitPoints = []; options.equalClips = 3
        let equal = try MediaEngine.tool(.splitVideo, inputs: [f.video], options: options, token: .init())
        XCTAssertEqual(equal.count, 3)
        XCTAssertNotEqual(equal[0].deletingLastPathComponent(),custom[0].deletingLastPathComponent())
        for clip in equal { XCTAssertEqual(try MediaEngine.inspect(clip).duration, 1, accuracy: 0.15) }
        options.equalClips = nil; options.splitInterval = 1.2
        let interval = try MediaEngine.tool(.splitVideo, inputs: [f.video], options: options, token: .init())
        XCTAssertEqual(interval.count, 3)
        XCTAssertEqual(try MediaEngine.inspect(interval[2]).duration, 0.6, accuracy: 0.15)
        XCTAssertEqual(try Data(contentsOf:f.video),original)
    }

    func testNormalizeReachesLoudnessAndChannelsApplyGain() throws {
        let f = try Fixtures(); defer { f.remove() }
        let before = try MediaEngine.measureLoudness(f.audio)
        let normalized = try output(.normalizeAudio, input: f.audio)
        let after = try MediaEngine.measureLoudness(normalized)
        XCTAssertLessThan(before.integrated, -35)
        XCTAssertEqual(after.integrated, -16, accuracy: 0.6)
        XCTAssertLessThanOrEqual(after.truePeak, -1.4)
        var options = OperationOptions(); options.channels = 1
        let mono = try output(.audioChannels, input: f.audio, options: options)
        XCTAssertEqual(try MediaEngine.inspect(mono).audio?.channels, 1)
        options.channels = 2; options.leftVolume = 0; options.rightVolume = 0.5
        let stereo = try output(.audioChannels, input: mono, options: options)
        XCTAssertEqual(try MediaEngine.inspect(stereo).audio?.channels, 2)
        let left = try samples(stereo, start: 0.5, duration: 0.2, channel: 0)
        let right = try samples(stereo, start: 0.5, duration: 0.2, channel: 1)
        XCTAssertLessThan(rms(left), 0.00001); XCTAssertGreaterThan(rms(right), 0.001)
        let leftPreview = try MediaEngine.previewChannel(f.audio, channel: 0, options: options)
        let rightPreview = try MediaEngine.previewChannel(f.audio, channel: 1, options: options)
        defer { try? FileManager.default.removeItem(at: leftPreview.deletingLastPathComponent()); try? FileManager.default.removeItem(at: rightPreview.deletingLastPathComponent()) }
        XCTAssertEqual(try MediaEngine.inspect(leftPreview).audio?.channels, 1)
        XCTAssertLessThan(rms(try samples(leftPreview, start: 0.5, duration: 0.2)), 0.00001)
        XCTAssertGreaterThan(rms(try samples(rightPreview, start: 0.5, duration: 0.2)), 0.001)
    }

    func testAudioVisualizerStylesContainVideoAndAudio() throws {
        let f = try Fixtures(); defer { f.remove() }
        for style in ["waveform", "spectrum", "bars"] {
            var options = OperationOptions(); options.width = 128; options.height = 96; options.visualizationStyle = style
            let visualized = try output(.audioToVideo, input: f.audio, options: options)
            let info = try MediaEngine.inspect(visualized)
            XCTAssertEqual(info.video?.width, 128, style); XCTAssertEqual(info.video?.height, 96, style)
            XCTAssertTrue(info.hasAudio, style); XCTAssertEqual(info.duration, 3, accuracy: 0.12, style)
            let pixels = try frame(visualized, time: 1)
            XCTAssertGreaterThan(pixels.filter { $0 > 30 }.count, 20, style)
        }
        var options = OperationOptions(); options.width = 128; options.height = 96; options.visualizationStyle = "image"
        options.visualizationImage = try output(.videoSnapshots, input: f.silent)
        let still = try output(.audioToVideo, input: f.audio, options: options)
        XCTAssertEqual(try MediaEngine.inspect(still).duration, 3, accuracy: 0.12)
        let pixels = try frame(still, time: 1)
        let center = (48 * 128 + 64) * 3
        XCTAssertLessThan(pixels[center], 20); XCTAssertGreaterThan(pixels[center + 2], 220)
        XCTAssertGreaterThan(pixels[0], 230) // White padding retains the image's aspect ratio.
    }

    func testAudioRedactionsMuteOrBleepOnlySelectedIntervals() throws {
        let f = try Fixtures(); defer { f.remove() }
        var options = OperationOptions(); options.audioRedactions = [TimeRange(start: 0.5, end: 1), TimeRange(start: 2, end: 2.5)]; options.audioMode = "mute"
        let muted = try output(.redactAudio, input: f.audio, options: options)
        XCTAssertLessThan(rms(try samples(muted, start: 0.65, duration: 0.2)), 0.00001)
        XCTAssertLessThan(rms(try samples(muted, start: 0.505, duration: 0.005)), 0.00001)
        XCTAssertGreaterThan(rms(try samples(muted, start: 1.2, duration: 0.2)), 0.003)
        options.audioMode = "bleep"
        let bleeped = try output(.redactAudio, input: f.audio, options: options)
        let tone = try samples(bleeped, start: 0.65, duration: 0.2)
        XCTAssertEqual(Double(zeroCrossings(tone)) / 0.4, 1000, accuracy: 15)
        XCTAssertGreaterThan(rms(tone), 0.04)
        XCTAssertEqual(rms(try samples(bleeped, start: 1.2, duration: 0.2)), rms(try samples(f.audio, start: 1.2, duration: 0.2)), accuracy: 0.0001)
        XCTAssertEqual(try MediaEngine.inspect(bleeped).duration, 3, accuracy: 0.03)
    }

    func testVideoRedactionStylesAndTemporalBounds() throws {
        let f = try Fixtures(); defer { f.remove() }
        for style in ["solid", "black", "blur", "pixelate"] {
            var options = OperationOptions(); options.redactions = [EditRect(x: 16, y: 16, width: 64, height: 48)]; options.redactionMode = style; options.backgroundColor = "#000000"; options.start = 0.5; options.end = 1.5
            let redacted = try output(.redactVideo, input: f.video, options: options)
            XCTAssertTrue(try MediaEngine.inspect(redacted).hasAudio)
            let frame = try self.frame(redacted, time: 1)
            XCTAssertEqual(frame.count, 128 * 96 * 3)
            if style == "solid" || style == "black" {
                let offset = (32 * 128 + 32) * 3
                XCTAssertLessThan(frame[offset], 10); XCTAssertLessThan(frame[offset + 1], 10); XCTAssertLessThan(frame[offset + 2], 10)
                let outsideInterval = try self.frame(redacted, time: 2)
                XCTAssertGreaterThan(Int(outsideInterval[offset]) + Int(outsideInterval[offset + 1]) + Int(outsideInterval[offset + 2]), 30)
            }
        }
        var options = OperationOptions(); options.redactionMode = "solid"; options.backgroundColor = "#000000"
        options.videoRedactions = [VideoRedaction(rect: EditRect(x: 16, y: 16, width: 32, height: 32), start: 0.25, end: 1), VideoRedaction(rect: EditRect(x: 64, y: 16, width: 32, height: 32), start: 1.5, end: 2.5)]
        let separate = try output(.redactVideo, input: f.video, options: options)
        let early = try frame(separate, time: 0.5), late = try frame(separate, time: 2)
        let first = (32 * 128 + 32) * 3, second = (32 * 128 + 80) * 3
        XCTAssertLessThan(Int(early[first]) + Int(early[first + 1]) + Int(early[first + 2]), 30)
        XCTAssertGreaterThan(Int(late[first]) + Int(late[first + 1]) + Int(late[first + 2]), 30)
        XCTAssertLessThan(Int(late[second]) + Int(late[second + 1]) + Int(late[second + 2]), 30)
    }

    func testCompressionMeetsActualByteAndPercentageTargets() throws {
        let f = try Fixtures(); defer { f.remove() }
        var options = OperationOptions(); options.targetBytes = 45000
        let compressed = try output(.compress, input: f.video, options: options)
        XCTAssertLessThanOrEqual(try size(compressed), 45000)
        XCTAssertTrue(try MediaEngine.inspect(compressed).hasAudio)
        XCTAssertEqual(try MediaEngine.inspect(compressed).duration, 3, accuracy: 0.15)
        options.targetBytes = nil; options.percentage = 60
        let audio = try output(.compress, input: f.audio, options: options)
        XCTAssertLessThanOrEqual(try size(audio), Int64(Double(try size(f.audio)) * 0.4))
        XCTAssertEqual(audio.pathExtension, "m4a")
        XCTAssertGreaterThan(rms(try samples(audio, start: 0.5, duration: 0.2)), 0.001)
    }

    func testRotatedVideosUseTheDisplayedCanvasForEditing() throws {
        let f = try Fixtures(); defer { f.remove() }
        let rotated = f.directory.appendingPathComponent("Phone portrait.mp4")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-display_rotation", "90", "-i", f.video.path, "-map", "0", "-c", "copy", rotated.path])
        let info = try MediaEngine.inspect(rotated)
        XCTAssertEqual(info.video?.width, 96); XCTAssertEqual(info.video?.height, 128)
        XCTAssertEqual(abs(info.video?.rotation ?? 0), 90)
        var options = OperationOptions(); options.crop = EditRect(x: 8, y: 16, width: 48, height: 64)
        let cropped = try output(.cropVideo, input: rotated, options: options)
        let result = try MediaEngine.inspect(cropped)
        XCTAssertEqual(result.video?.width, 48); XCTAssertEqual(result.video?.height, 64)
        XCTAssertTrue(result.hasAudio)
    }

    func testMetadataCanBeInspectedEditedAndRemovedWithoutTouchingSource() throws {
        let f = try Fixtures(); defer { f.remove() }
        let source = try Data(contentsOf: f.video)
        let metadata = try MediaEngine.readMetadata(f.video)
        XCTAssertEqual(metadata["file:title"], "Private source title")
        XCTAssertEqual(metadata["track[1]:language"], "eng")
        let edited = try XCTUnwrap(MediaEngine.editMetadata(f.video, metadata: ["file:title": "New title", "file:comment": "", "track[1]:language": "tur"]).first)
        let editedMetadata = try MediaEngine.readMetadata(edited)
        XCTAssertEqual(editedMetadata["file:title"], "New title")
        XCTAssertEqual(editedMetadata["track[1]:language"], "tur")
        XCTAssertNil(editedMetadata["file:comment"])
        let removed = try output(.removeMetadata, input: f.video)
        let removedMetadata = try MediaEngine.readMetadata(removed)
        XCTAssertNil(removedMetadata["file:title"]); XCTAssertNil(removedMetadata["file:comment"])
        XCTAssertEqual(try MediaEngine.inspect(removed).video?.codec, "h264")
        XCTAssertEqual(try Data(contentsOf: f.video), source)
        let chapterFile = f.directory.appendingPathComponent("Chapters.ffmeta")
        try ";FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=1500\ntitle=First scene\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=1500\nEND=3000\ntitle=Second scene\n".write(to: chapterFile, atomically: true, encoding: .utf8)
        let chaptered = f.directory.appendingPathComponent("Chaptered.mkv")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-i", f.video.path, "-f", "ffmetadata", "-i", chapterFile.path, "-map", "0", "-map_chapters", "1", "-c", "copy", chaptered.path])
        XCTAssertEqual(try MediaEngine.inspect(chaptered).chapters.count, 2)
        let chapterEdited = try XCTUnwrap(MediaEngine.editMetadata(chaptered, metadata: ["chapter[1]:title": "Updated scene"]).first)
        XCTAssertEqual(try MediaEngine.inspect(chapterEdited).chapters[1].metadata.first { $0.key.lowercased() == "title" }?.value, "Updated scene")
        let chaptersRemoved = try output(.removeMetadata, input: chaptered)
        XCTAssertTrue(try MediaEngine.inspect(chaptersRemoved).chapters.isEmpty)
        let chapteredMP4 = f.directory.appendingPathComponent("Chaptered.mp4")
        try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-i", f.video.path, "-f", "ffmetadata", "-i", chapterFile.path, "-map", "0", "-map_chapters", "1", "-c", "copy", chapteredMP4.path])
        XCTAssertTrue(try MediaEngine.inspect(chapteredMP4).streams.contains { $0.kind == "data" })
        let mp4Removed = try output(.removeMetadata, input: chapteredMP4)
        let removedInfo = try MediaEngine.inspect(mp4Removed)
        XCTAssertTrue(removedInfo.chapters.isEmpty)
        XCTAssertFalse(removedInfo.streams.contains { $0.kind == "data" }, "Chapter payloads and camera telemetry must also be removed.")
    }

    func testValidationCancellationAndOutputDirectoryPreserveSources() throws {
        let f = try Fixtures(); defer { f.remove() }
        let cancelled = CancellationToken(); cancelled.cancel()
        XCTAssertThrowsError(try MediaEngine.convert(f.video, to: "mov", options: .init(), token: cancelled))
        var options = OperationOptions(); options.start = 2; options.end = 1
        XCTAssertThrowsError(try output(.trimVideo, input: f.video, options: options))
        options = .init(); options.crop = EditRect(x: -1, y: 0, width: 20, height: 20)
        XCTAssertThrowsError(try output(.cropVideo, input: f.video, options: options))
        XCTAssertThrowsError(try output(.trimVideo, input: f.audio))
        XCTAssertThrowsError(try MediaEngine.convert(f.video, to: "bogus", options: .init(), token: .init()))
        options = .init(); options.outputDirectory = f.directory.appendingPathComponent("Exports", isDirectory: true)
        let first = try output(.muteVideo, input: f.video, options: options)
        let firstContents = try Data(contentsOf: first)
        let second = try output(.muteVideo, input: f.video, options: options)
        XCTAssertEqual(first.deletingLastPathComponent(), options.outputDirectory)
        XCTAssertNotEqual(first, second); XCTAssertEqual(try Data(contentsOf: first), firstContents)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: options.outputDirectory!, includingPropertiesForKeys: nil).allSatisfy { !$0.lastPathComponent.hasPrefix(".nashi-") })
        let inFlight = CancellationToken()
        options.outputDirectory = f.directory.appendingPathComponent("Cancelled", isDirectory: true); options.width = 2048; options.height = 1536
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { inFlight.cancel() }
        XCTAssertThrowsError(try MediaEngine.convert(f.video, to: "webm", options: options, token: inFlight)) { error in
            guard case NashiError.cancelled = error else { return XCTFail("Expected cancellation, received \(error)") }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: options.outputDirectory!, includingPropertiesForKeys: nil).isEmpty)
    }

    private func output(_ kind: ToolKind, input: URL, options: OperationOptions = .init()) throws -> URL {
        let outputs = try MediaEngine.tool(kind, inputs: [input], options: options, token: .init())
        return try XCTUnwrap(outputs.first)
    }
    private func size(_ url: URL) throws -> Int64 { Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    private func samples(_ url: URL, start: Double, duration: Double, channel: Int? = nil) throws -> [Float] {
        var arguments = ["-v", "error", "-ss", String(start), "-i", url.path, "-t", String(duration), "-map", "0:a:0"]
        if let channel { arguments += ["-af", "pan=mono|c0=c\(channel)"] }
        arguments += ["-ac", "1", "-ar", "48000", "-f", "f32le", "-"]
        let bytes = try ProcessRunner.run(Dependencies.executable("ffmpeg"), arguments).output
        return bytes.withUnsafeBytes { buffer in stride(from: 0, to: buffer.count - 3, by: 4).map { buffer.loadUnaligned(fromByteOffset: $0, as: Float.self) } }
    }
    private func frame(_ url: URL, time: Double) throws -> [UInt8] {
        Array(try ProcessRunner.run(Dependencies.executable("ffmpeg"), ["-v", "error", "-ss", String(time), "-i", url.path, "-map", "0:v:0", "-frames:v", "1", "-pix_fmt", "rgb24", "-f", "rawvideo", "-"]).output)
    }
    private func rms(_ values: [Float]) -> Double { values.isEmpty ? 0 : sqrt(values.reduce(0) { $0 + Double($1 * $1) } / Double(values.count)) }
    private func zeroCrossings(_ values: [Float]) -> Int { zip(values, values.dropFirst()).filter { ($0.0 < 0) != ($0.1 < 0) }.count }
}
