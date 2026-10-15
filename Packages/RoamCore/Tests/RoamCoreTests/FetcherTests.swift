import XCTest
@testable import RoamCore

final class FetcherTests: XCTestCase {
    private let request = URLRequest(url: URL(string: "https://example.com/data")!)
    private let ttl: TimeInterval = 600
    private let decode: (Data) throws -> String = { data in
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("v") else { throw APIError.decoding("bad") }
        return text
    }

    private struct Rig {
        let clock = Clock()
        let cache: MemoryCache
        let client: MockClient
        let fetcher: CachedFetcher

        init(_ handler: @escaping @Sendable (URLRequest) throws -> Data) {
            let clock = self.clock
            cache = MemoryCache(now: { clock.now })
            client = MockClient(handler)
            fetcher = CachedFetcher(client: client, cache: cache, now: { clock.now })
        }
    }

    func testFirstLoadHitsTheNetworkAndCaches() async throws {
        let rig = Rig { _ in Data("v1".utf8) }
        let loaded = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        XCTAssertEqual(loaded.value, "v1")
        XCTAssertEqual(loaded.source, .network)
        XCTAssertEqual(rig.cache.entry(for: request.url!.absoluteString)?.data, Data("v1".utf8))
    }

    func testFreshCacheAnswersWithoutARequest() async throws {
        let rig = Rig { _ in Data("v1".utf8) }
        _ = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        rig.clock.advance(120)
        let loaded = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        XCTAssertEqual(rig.client.count, 1)
        XCTAssertEqual(loaded.source, .cache(age: 120, stale: false))
        XCTAssertFalse(loaded.isStale)
    }

    func testExpiredCacheGoesBackToTheNetwork() async throws {
        let rig = Rig { _ in Data("v\(Int.random(in: 100...999))".utf8) }
        let first = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        rig.clock.advance(ttl + 1)
        let second = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        XCTAssertEqual(rig.client.count, 2)
        XCTAssertEqual(second.source, .network)
        XCTAssertNotEqual(first.value, second.value)
        XCTAssertEqual(rig.cache.entry(for: request.url!.absoluteString)?.data, Data(second.value.utf8))
    }

    func testOfflineWithAnOldCopyServesItAsStale() async throws {
        let failing = LockedFlag()
        let rig = Rig { _ in
            if failing.value { throw APIError.offline }
            return Data("v1".utf8)
        }
        _ = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        rig.clock.advance(3 * 3600)
        failing.value = true
        let loaded = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        XCTAssertEqual(loaded.value, "v1")
        XCTAssertEqual(loaded.source, .cache(age: 3 * 3600, stale: true))
        XCTAssertTrue(loaded.isStale)
    }

    func testOfflineWithNothingCachedThrowsTheError() async {
        let rig = Rig { _ in throw APIError.offline }
        do { _ = try await rig.fetcher.load(request, ttl: ttl, decode: decode); XCTFail("should throw") } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
    }

    func testForceRefreshSkipsAFreshCopyButStillFallsBack() async throws {
        let failing = LockedFlag()
        let rig = Rig { _ in
            if failing.value { throw APIError.timeout }
            return Data("v\(Int.random(in: 100...999))".utf8)
        }
        let first = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        let refreshed = try await rig.fetcher.load(request, ttl: ttl, forceRefresh: true, decode: decode)
        XCTAssertEqual(rig.client.count, 2)
        XCTAssertEqual(refreshed.source, .network)
        _ = first
        failing.value = true
        let fallback = try await rig.fetcher.load(request, ttl: ttl, forceRefresh: true, decode: decode)
        XCTAssertEqual(fallback.value, refreshed.value)
        XCTAssertTrue(fallback.isStale)
    }

    func testABadResponseIsNeverCachedAndTheOldCopyIsKept() async throws {
        let bad = LockedFlag()
        let rig = Rig { _ in bad.value ? Data("<html>oops".utf8) : Data("v1".utf8) }
        _ = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        rig.clock.advance(ttl + 1)
        bad.value = true
        let loaded = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        XCTAssertEqual(loaded.value, "v1")
        XCTAssertTrue(loaded.isStale)
        XCTAssertEqual(rig.cache.entry(for: request.url!.absoluteString)?.data, Data("v1".utf8))
    }

    func testABadResponseWithNothingCachedIsADecodingError() async {
        let rig = Rig { _ in Data("<html>".utf8) }
        do { _ = try await rig.fetcher.load(request, ttl: ttl, decode: decode); XCTFail("should throw") } catch {
            guard case APIError.decoding = error else { return XCTFail("\(error)") }
        }
        XCTAssertNil(rig.cache.entry(for: request.url!.absoluteString))
    }

    func testACorruptCacheEntryIsTreatedAsMissing() async throws {
        let rig = Rig { _ in Data("v2".utf8) }
        rig.cache.store(Data("garbage".utf8), for: request.url!.absoluteString)
        let loaded = try await rig.fetcher.load(request, ttl: ttl, decode: decode)
        XCTAssertEqual(loaded.value, "v2")
        XCTAssertEqual(loaded.source, .network)
    }

    func testCancellationIsNotTurnedIntoStaleData() async {
        let cancelled = LockedFlag()
        let rig = Rig { _ in
            if cancelled.value { throw CancellationError() }
            return Data("v1".utf8)
        }
        _ = try? await rig.fetcher.load(request, ttl: ttl, decode: decode)
        rig.clock.advance(ttl + 1)
        cancelled.value = true
        do { _ = try await rig.fetcher.load(request, ttl: ttl, decode: decode); XCTFail("should throw") } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testDifferentURLsHaveSeparateEntries() async throws {
        let rig = Rig { request in Data("v-\(request.url!.lastPathComponent)".utf8) }
        let a = try await rig.fetcher.load(URLRequest(url: URL(string: "https://example.com/a")!), ttl: ttl, decode: decode)
        let b = try await rig.fetcher.load(URLRequest(url: URL(string: "https://example.com/b")!), ttl: ttl, decode: decode)
        XCTAssertEqual([a.value, b.value], ["v-a", "v-b"])
        XCTAssertEqual(rig.client.count, 2)
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}
