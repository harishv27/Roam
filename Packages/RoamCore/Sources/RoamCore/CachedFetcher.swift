import Foundation

/// A decoded value and where it came from, so the screen can say "Updated 3 hours ago" when it is not live.
public struct Loaded<Value> {
    public enum Source: Equatable {
        case network
        /// `stale` means the entry was older than its time-to-live and is only shown because the network failed.
        case cache(age: TimeInterval, stale: Bool)
    }

    public let value: Value
    public let source: Source

    public init(value: Value, source: Source) { self.value = value; self.source = source }

    public var isStale: Bool { if case .cache(_, let stale) = source { return stale } else { return false } }
}

extension Loaded: Equatable where Value: Equatable {}

/// Network with a cache behind it:
///
/// 1. A cached copy younger than `ttl` is returned straight away (no request).
/// 2. Otherwise the network is asked. A good answer is cached and returned.
/// 3. If the network fails, an older cached copy is returned as stale; with nothing cached the error is thrown.
///
/// Step 3 is what lets a saved place open on a plane. A response that cannot be decoded is never cached, and a cached
/// one that no longer decodes is treated as missing.
public struct CachedFetcher: Sendable {
    private let client: HTTPClient
    private let cache: ResponseCache
    private let now: @Sendable () -> Date

    public init(client: HTTPClient, cache: ResponseCache, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.cache = cache; self.now = now
    }

    public func load<Value>(_ request: URLRequest, ttl: TimeInterval, forceRefresh: Bool = false,
                            decode: (Data) throws -> Value) async throws -> Loaded<Value> {
        let key = request.url?.absoluteString ?? ""
        let cached: (value: Value, age: TimeInterval)? = cache.entry(for: key).flatMap { entry in
            (try? decode(entry.data)).map { ($0, max(0, now().timeIntervalSince(entry.storedAt))) }
        }

        if let cached, !forceRefresh, cached.age < ttl {
            return Loaded(value: cached.value, source: .cache(age: cached.age, stale: false))
        }

        do {
            let (data, _) = try await client.send(request)
            let value = try decode(data)
            cache.store(data, for: key)
            return Loaded(value: value, source: .network)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let cached { return Loaded(value: cached.value, source: .cache(age: cached.age, stale: true)) }
            throw error as? APIError ?? APIError.connection
        }
    }
}
