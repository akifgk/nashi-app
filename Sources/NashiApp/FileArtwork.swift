import AppKit
import SwiftUI

/// File identity is checked on the worker, never while SwiftUI evaluates a row.
struct FileArtworkStamp: Equatable, Sendable {
    let exists: Bool
    let modified: TimeInterval
    let size: UInt64
    let directory: Bool
    static func read(_ url: URL) -> Self {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return .init(exists: false, modified: 0, size: 0, directory: false)
        }
        return .init(exists: true,
                     modified: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                     size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                     directory: attributes[.type] as? FileAttributeType == .typeDirectory)
    }
}

/// macOS 13 predates AppKit's NSImage Sendable annotation. Ownership crosses the
/// worker boundary once in this immutable envelope: Nashi never mutates the image,
/// the cache only stores its reference, and consumers only render it on the UI actor.
/// This avoids retroactively declaring every NSImage instance safe to share.
final class FileArtworkImage: @unchecked Sendable {
    let image: NSImage
    init(_ image: NSImage) { self.image = image }
}

/// One shared flight per path; bounded LRU entries include missing-file icons.
/// NSWorkspace's returned images are only read after the worker hands them to the UI.
actor FileArtworkCache {
    static let shared = FileArtworkCache()
    typealias Loader = @Sendable (URL) -> NSImage?
    typealias StampReader = @Sendable (URL) -> FileArtworkStamp
    private struct Entry { let stamp: FileArtworkStamp; let image: FileArtworkImage?; var access: UInt64 }
    private let capacity: Int
    private let loader: Loader
    private let stampReader: StampReader
    private var cache: [String: Entry] = [:]
    private var flights: [String: Task<FileArtworkImage?, Never>] = [:]
    private var clock: UInt64 = 0

    init(capacity: Int = 128, stampReader: @escaping StampReader = { FileArtworkStamp.read($0) },
         loader: @escaping Loader = { NSWorkspace.shared.icon(forFile: $0.path) }) {
        self.capacity = max(1, capacity); self.stampReader = stampReader; self.loader = loader
    }
    func image(for url: URL) async -> FileArtworkImage? {
        let url = url.standardizedFileURL, key = url.path
        if let flight = flights[key] { return await flight.value }
        let flight = Task { await load(url, key: key) }
        flights[key] = flight
        let image = await flight.value
        flights[key] = nil
        return image
    }
    private func load(_ url: URL, key: String) async -> FileArtworkImage? {
        let reader = stampReader
        let stamp = await Task.detached(priority: .utility) { reader(url) }.value
        clock &+= 1
        if var entry = cache[key], entry.stamp == stamp {
            entry.access = clock; cache[key] = entry; return entry.image
        }
        let loader = loader
        let image = await Task.detached(priority: .utility) { loader(url).map { FileArtworkImage($0) } }.value
        clock &+= 1
        if let image { cache[key] = Entry(stamp: stamp, image: image, access: clock) }
        else { cache[key] = nil }
        while cache.count > capacity, let oldest = cache.min(by: { $0.value.access < $1.value.access })?.key {
            cache[oldest] = nil
        }
        return image
    }
    var cachedCount: Int { cache.count }
    var pendingCount: Int { flights.count }
}

/// Keeps semantic Finder artwork and the existing row geometry while loading off the UI queue.
struct AsyncFileArtwork: View {
    let url: URL
    @State private var image: NSImage?
    @State private var activation: UInt64 = 0
    private var identity: String { url.standardizedFileURL.path + "\u{0}" + String(activation) }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable() }
            else { Image(systemName: "doc").resizable().scaledToFit().foregroundStyle(.secondary) }
        }
        .task(id: identity) {
            image = nil
            let loaded = await FileArtworkCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded?.image
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in activation &+= 1 }
        .accessibilityHidden(true)
    }
}
