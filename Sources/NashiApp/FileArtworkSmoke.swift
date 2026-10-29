import AppKit
import os

/// An isolated, opt-in cache/queue probe. No user's Library or clipboard is read or changed.
@MainActor enum FileArtworkSmoke {
    static func run(output: URL) async throws -> [String: Any] {
        struct Probe { var loads = 0; var version: UInt64 = 1; var exists = true; var onMain = false; var lags: [Double] = [] }
        let probe = OSAllocatedUnfairLock(initialState: Probe())
        var checks: [String] = []
        func check(_ success: Bool, _ label: String) throws {
            guard success else { throw NSError(domain: "Nashi File Artwork QA", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        let slow: FileArtworkCache.Loader = { _ in
            let start = Date()
            probe.withLock { $0.loads += 1; $0.onMain = $0.onMain || Thread.isMainThread }
            DispatchQueue.main.async { probe.withLock { $0.lags.append(Date().timeIntervalSince(start) * 1000) } }
            Thread.sleep(forTimeInterval: 0.08)
            return NSImage(size: NSSize(width: 32, height: 32))
        }
        let url = output.appendingPathComponent("cache-probe.pdf")
        // Reproduce the former render path with exactly the same slow provider.
        for _ in 0..<8 { _ = slow(url) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { continuation.resume() } }
        let baselineLag = probe.withLock { $0.lags.max() ?? 0 }
        probe.withLock { $0.loads = 0; $0.onMain = false; $0.lags = [] }
        let cache = FileArtworkCache(capacity: 2, stampReader: { _ in
            probe.withLock { $0.onMain = $0.onMain || Thread.isMainThread; return FileArtworkStamp(exists: $0.exists, modified: Double($0.version), size: $0.version, directory: false) }
        }, loader: slow)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { _ = await cache.image(for: url) } }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { continuation.resume() } }
        let asyncLoads = probe.withLock { $0.loads }, asyncLag = probe.withLock { $0.lags.max() ?? 0 }
        try check(asyncLoads == 1, "Eight simultaneous rows share one artwork load")
        try check(!probe.withLock { $0.onMain }, "Slow artwork and metadata loading never runs on the UI queue")
        try check(asyncLag < baselineLag / 2, "UI queue remains responsive while the injected icon provider is slow")
        for _ in 0..<8 { _ = await cache.image(for: url) }
        try check(probe.withLock { $0.loads } == 1, "Warm requests reuse artwork instead of calling the OS icon provider")
        probe.withLock { $0.version += 1 }; _ = await cache.image(for: url)
        try check(probe.withLock { $0.loads } == 2, "Changed file metadata invalidates its artwork")
        probe.withLock { $0.exists = false }; _ = await cache.image(for: url)
        try check(probe.withLock { $0.loads } == 3, "Missing files get a fresh semantic association icon")
        probe.withLock { $0.exists = true }; _ = await cache.image(for: url)
        try check(probe.withLock { $0.loads } == 4, "Recreated files replace cached missing-file artwork")
        _ = await cache.image(for: output.appendingPathComponent("b.png"))
        _ = await cache.image(for: output.appendingPathComponent("c.txt"))
        try check(await cache.cachedCount == 2, "Cache stays within its configured entry limit")
        _ = await cache.image(for: url)
        try check(probe.withLock { $0.loads } == 7, "Least recently used artwork is evicted and can be loaded again")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: url)
        let firstStamp = await Task.detached { FileArtworkStamp.read(url) }.value
        try Data("changed fixture length".utf8).write(to: url)
        let changedStamp = await Task.detached { FileArtworkStamp.read(url) }.value
        try check(firstStamp.exists && changedStamp.exists && firstStamp != changedStamp, "Real filesystem stamps detect replacement without UI-thread file I/O")
        let nativeStart = Date(), native = await FileArtworkCache.shared.image(for: url)
        let nativeCold = Date().timeIntervalSince(nativeStart) * 1000
        let warmStart = Date(); _ = await FileArtworkCache.shared.image(for: url)
        let nativeWarm = Date().timeIntervalSince(warmStart) * 1000
        try check(native != nil, "The release worker returns the actual Finder file icon")
        let result: [String: Any] = ["passed": checks.count, "checks": checks, "baselineProviderCalls": 8,
            "asyncProviderCalls": asyncLoads, "baselineUIQueueDelayMs": baselineLag, "asyncUIQueueDelayMs": asyncLag,
            "nativeColdMs": nativeCold, "nativeWarmMs": nativeWarm,
            "scope": "Injected slow provider and real Finder icon; isolated files, no Library or clipboard access."]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("file-artwork.json"))
        return result
    }
}
