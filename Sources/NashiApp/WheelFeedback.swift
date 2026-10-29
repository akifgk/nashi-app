import AppKit
import AVFAudio
import Foundation

/// Retains prepared audio players so a wheel selection never creates a sound object.
@MainActor final class WheelFeedback {
    static let shared = WheelFeedback()

    struct Attempt: Equatable {
        enum Outcome: String { case disabled, throttled, requested }
        let outcome: Outcome
        let soundStarted: Bool
        let hapticRequested: Bool
    }

    struct Probe: Codable {
        let enabled: Bool
        let poolSize: Int
        let preparedPlayers: Int
        let tickDuration: TimeInterval
        let minimumInterval: TimeInterval
        let audioError: String?
    }

    private let defaults: UserDefaults
    private let clock: () -> TimeInterval
    private let injectedSound: (() -> Bool)?
    private let performHaptic: () -> Void
    private let players: [AVAudioPlayer]
    private var prepared: [Bool]
    private var playerIndex = 0
    private var lastRequest: TimeInterval?
    private var audioError: String?
    private let minimumInterval: TimeInterval = 0.05

    // Injectable effects allow preference/throttle checks without producing physical feedback.
    init(defaults: UserDefaults = .standard,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         playSound: (() -> Bool)? = nil,
         selectionSoundURL: URL? = nil,
         performHaptic: (() -> Void)? = nil) {
        self.defaults = defaults
        self.clock = clock
        self.injectedSound = playSound
        self.performHaptic = performHaptic ?? {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        var pool: [AVAudioPlayer] = []
        var preparation: [Bool] = []
        var failure: String?
        if playSound == nil {
            if let url = selectionSoundURL ?? Self.soundURL {
              for _ in 0..<3 {
                do {
                    let player = try AVAudioPlayer(contentsOf: url)
                    player.volume = 0.65
                    player.numberOfLoops = 0
                    pool.append(player)
                    preparation.append(player.prepareToPlay())
                } catch {
                    failure = error.localizedDescription
                }
              }
            } else {
                failure = "The wheel selection sound is missing."
            }
        }
        self.players = pool
        self.prepared = preparation
        self.audioError = failure ?? (!pool.isEmpty && !preparation.contains(true) ? "Audio output could not be prepared." : nil)
    }

    /// Call when presenting the wheel to warm the pool before the first hover.
    @discardableResult func prepare() -> Probe {
        for index in players.indices where !prepared[index] {
            prepared[index] = players[index].prepareToPlay()
        }
        return probe()
    }

    @discardableResult func selectionChanged() -> Attempt {
        guard enabled else {
            for index in players.indices { players[index].stop(); prepared[index] = false }
            lastRequest = nil
            return Attempt(outcome: .disabled, soundStarted: false, hapticRequested: false)
        }
        let now = clock()
        if let lastRequest, now >= lastRequest, now - lastRequest < minimumInterval {
            return Attempt(outcome: .throttled, soundStarted: false, hapticRequested: false)
        }
        lastRequest = now
        let started: Bool
        if let injectedSound {
            started = injectedSound()
        } else if !players.isEmpty {
            let index = playerIndex
            let player = players[index]
            playerIndex = (index + 1) % players.count
            if player.isPlaying { player.stop(); prepared[index] = false }
            player.currentTime = 0
            if !prepared[index] { prepared[index] = player.prepareToPlay() }
            started = player.play()
            if started { audioError = nil }
            else { prepared[index] = false; audioError = "Audio playback could not start." }
        } else {
            started = false
        }
        performHaptic()
        return Attempt(outcome: .requested, soundStarted: started, hapticRequested: true)
    }

    /// A Settings test uses the same preference and rate limit as the wheel.
    @discardableResult func testPreview() -> Attempt { selectionChanged() }

    /// Reports API/preparation state, never whether a speaker or trackpad was perceived.
    func probe() -> Probe {
        Probe(enabled: enabled, poolSize: players.count,
              preparedPlayers: prepared.filter { $0 }.count,
              tickDuration: players.first?.duration ?? 0,
              minimumInterval: minimumInterval, audioError: audioError)
    }

    private var enabled: Bool {
        if let value = defaults.object(forKey: "soundsAndHapticsEnabled") as? Bool { return value }
        if defaults.object(forKey: "sound") != nil { return defaults.bool(forKey: "sound") }
        return true
    }

    /// The supplied WAV is bundled verbatim, including its short natural decay.
    private static var soundURL: URL? {
        if let url = Bundle.main.url(forResource: "WheelSelection", withExtension: "wav", subdirectory: "Sounds") {
            return url
        }
        #if DEBUG
        let development = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Sounds/WheelSelection.wav")
        if FileManager.default.fileExists(atPath: development.path) { return development }
        #endif
        return nil
    }
}
