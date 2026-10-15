import XCTest
@testable import RoamCore

final class ServiceTests: XCTestCase {
    private func routed(_ calls: LockedCount? = nil) -> MockClient {
        MockClient { request in
            calls?.increment()
            switch request.url?.host {
            case "geocoding-api.open-meteo.com": return fixture("geocoding-lisbon")
            case "api.open-meteo.com": return fixture("forecast-lisbon")
            case "en.wikipedia.org": return fixture("wikipedia-nearby-lisbon")
            default: throw APIError.invalidResponse
            }
        }
    }

    func testSearchReturnsPlacesAndCachesThem() async throws {
        let client = routed()
        let service = RoamService(client: client, cache: MemoryCache())
        let first = try await service.searchPlaces("Lisbon")
        XCTAssertEqual(first.value.first?.name, "Lisbon")
        _ = try await service.searchPlaces("  LISBON ")          // same search after trimming and lower-casing
        XCTAssertEqual(client.count, 1)
    }

    func testShortQueriesNeverReachTheNetwork() async throws {
        let client = routed()
        let service = RoamService(client: client, cache: MemoryCache())
        let result = try await service.searchPlaces(" a ")
        XCTAssertEqual(result.value, [])
        XCTAssertEqual(client.count, 0)
    }

    func testForecastAndAttractions() async throws {
        let service = RoamService(client: routed(), cache: MemoryCache())
        let forecast = try await service.forecast(for: lisbon)
        XCTAssertEqual(forecast.value.days.count, 7)
        let attractions = try await service.attractions(near: lisbon)
        XCTAssertFalse(attractions.value.isEmpty)
        XCTAssertFalse(attractions.value.contains { $0.title == "Taifa of Lisbon" })
    }

    func testSavedPlaceOpensOfflineFromTheCache() async throws {
        let cache = MemoryCache()
        let online = RoamService(client: routed(), cache: cache)
        _ = try await online.forecast(for: lisbon)
        _ = try await online.attractions(near: lisbon)

        let offline = RoamService(client: MockClient { _ in throw APIError.offline }, cache: cache)
        let forecast = try await offline.forecast(for: lisbon, forceRefresh: true)
        let attractions = try await offline.attractions(near: lisbon, forceRefresh: true)
        XCTAssertEqual(forecast.value.days.count, 7)
        XCTAssertTrue(forecast.isStale)
        XCTAssertFalse(attractions.value.isEmpty)
        XCTAssertTrue(attractions.isStale)
    }

    func testAPlaceNeverOpenedHasNothingOffline() async {
        let offline = RoamService(client: MockClient { _ in throw APIError.offline }, cache: MemoryCache())
        do { _ = try await offline.forecast(for: lisbon); XCTFail("should throw") } catch {
            XCTAssertEqual(error as? APIError, .offline)
        }
    }
}

final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
