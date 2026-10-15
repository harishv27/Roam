import Foundation
import CryptoKit

public struct CacheEntry: Equatable, Sendable {
    public let data: Data
    public let storedAt: Date
}

public protocol ResponseCache: Sendable {
    func entry(for key: String) -> CacheEntry?
    func store(_ data: Data, for key: String)
    func remove(_ key: String)
}

/// A cache that lives as long as the process. Used in tests and previews.
public final class MemoryCache: ResponseCache, @unchecked Sendable {
    private var entries: [String: CacheEntry] = [:]
    private let lock = NSLock()
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) { self.now = now }

    public func entry(for key: String) -> CacheEntry? { lock.withLock { entries[key] } }
    public func store(_ data: Data, for key: String) { lock.withLock { entries[key] = CacheEntry(data: data, storedAt: now()) } }
    public func remove(_ key: String) { lock.withLock { _ = entries.removeValue(forKey: key) } }
}

/// One file per response in a folder (the app uses Caches, so the system may clear it). When it was stored is the
/// file's modification date, so there is no index to keep in step with the files.
public final class DiskCache: ResponseCache, @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest).appendingPathExtension("json")
    }

    public func entry(for key: String) -> CacheEntry? {
        lock.withLock {
            let url = file(for: key)
            guard let data = try? Data(contentsOf: url),
                  let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            else { return nil }
            return CacheEntry(data: data, storedAt: date)
        }
    }

    public func store(_ data: Data, for key: String) {
        lock.withLock { try? data.write(to: file(for: key), options: .atomic) }
    }

    public func remove(_ key: String) {
        lock.withLock { try? FileManager.default.removeItem(at: file(for: key)) }
    }

    /// Deletes anything older than `age` seconds. Called at launch so the folder cannot grow forever.
    public func prune(olderThan age: TimeInterval, now: Date = Date()) {
        lock.withLock {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for url in urls {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if now.timeIntervalSince(date) > age { try? FileManager.default.removeItem(at: url) }
            }
        }
    }

    /// Test hook: pretend an entry was stored `age` seconds ago.
    func backdate(_ key: String, by age: TimeInterval) {
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file(for: key).path)
    }
}
