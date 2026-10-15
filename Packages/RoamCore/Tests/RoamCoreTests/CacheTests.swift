import XCTest
@testable import RoamCore

final class CacheTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("roam-tests-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    func testMemoryCacheRoundTrip() {
        let clock = Clock()
        let cache = MemoryCache(now: { clock.now })
        XCTAssertNil(cache.entry(for: "k"))
        cache.store(Data("v".utf8), for: "k")
        XCTAssertEqual(cache.entry(for: "k")?.data, Data("v".utf8))
        XCTAssertEqual(cache.entry(for: "k")?.storedAt, clock.now)
        cache.remove("k")
        XCTAssertNil(cache.entry(for: "k"))
    }

    func testDiskCacheRoundTripAndOverwrite() {
        let cache = DiskCache(directory: directory)
        cache.store(Data("one".utf8), for: "https://example.com/a?x=1")
        cache.store(Data("two".utf8), for: "https://example.com/b")
        XCTAssertEqual(cache.entry(for: "https://example.com/a?x=1")?.data, Data("one".utf8))
        XCTAssertEqual(cache.entry(for: "https://example.com/b")?.data, Data("two".utf8))
        cache.store(Data("three".utf8), for: "https://example.com/b")
        XCTAssertEqual(cache.entry(for: "https://example.com/b")?.data, Data("three".utf8))
        XCTAssertNil(cache.entry(for: "https://example.com/missing"))
    }

    func testDiskCacheSurvivesANewInstance() {
        DiskCache(directory: directory).store(Data("kept".utf8), for: "k")
        XCTAssertEqual(DiskCache(directory: directory).entry(for: "k")?.data, Data("kept".utf8))
    }

    func testStoredDateIsTheFileDate() throws {
        let cache = DiskCache(directory: directory)
        cache.store(Data("v".utf8), for: "k")
        cache.backdate("k", by: 3600)
        let age = Date().timeIntervalSince(try XCTUnwrap(cache.entry(for: "k")).storedAt)
        XCTAssertEqual(age, 3600, accuracy: 5)
    }

    func testRemoveAndPrune() {
        let cache = DiskCache(directory: directory)
        cache.store(Data("old".utf8), for: "old")
        cache.store(Data("new".utf8), for: "new")
        cache.store(Data("gone".utf8), for: "gone")
        cache.backdate("old", by: 40 * 86_400)
        cache.remove("gone")
        cache.prune(olderThan: 30 * 86_400)
        XCTAssertNil(cache.entry(for: "old"))
        XCTAssertNil(cache.entry(for: "gone"))
        XCTAssertNotNil(cache.entry(for: "new"))
    }

    func testKeysThatDifferByCaseOrQueryDoNotCollide() {
        let cache = DiskCache(directory: directory)
        cache.store(Data("1".utf8), for: "https://x.com/a?q=Lisbon")
        cache.store(Data("2".utf8), for: "https://x.com/a?q=lisbon")
        XCTAssertEqual(cache.entry(for: "https://x.com/a?q=Lisbon")?.data, Data("1".utf8))
        XCTAssertEqual(cache.entry(for: "https://x.com/a?q=lisbon")?.data, Data("2".utf8))
    }
}
