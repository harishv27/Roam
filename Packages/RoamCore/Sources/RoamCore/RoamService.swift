import Foundation

/// What the app talks to. Each call has its own time-to-live: place names almost never change, a forecast goes
/// stale in half an hour.
public struct RoamService: Sendable {
    public enum TTL {
        public static let search: TimeInterval = 7 * 86_400
        public static let forecast: TimeInterval = 30 * 60
        public static let attractions: TimeInterval = 7 * 86_400
    }

    private let fetcher: CachedFetcher

    public init(client: HTTPClient, cache: ResponseCache) {
        fetcher = CachedFetcher(client: client, cache: cache)
    }

    init(fetcher: CachedFetcher) { self.fetcher = fetcher }

    /// Cities matching the text. Under two characters there is nothing worth asking the server.
    public func searchPlaces(_ query: String) async throws -> Loaded<[Place]> {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard text.count >= 2 else { return Loaded(value: [], source: .cache(age: 0, stale: false)) }
        return try await fetcher.load(Endpoint.searchPlaces(query: text), ttl: TTL.search, decode: Decoding.places)
    }

    public func forecast(for place: Place, forceRefresh: Bool = false) async throws -> Loaded<Forecast> {
        try await fetcher.load(Endpoint.forecast(latitude: place.latitude, longitude: place.longitude),
                               ttl: TTL.forecast, forceRefresh: forceRefresh, decode: Decoding.forecast)
    }

    /// Ranked and trimmed: see `AttractionRanker`. The cache holds the raw response, so a change to the ranking applies
    /// to places that are already saved.
    public func attractions(near place: Place, forceRefresh: Bool = false) async throws -> Loaded<[Attraction]> {
        let origin = (latitude: place.latitude, longitude: place.longitude)
        return try await fetcher.load(Endpoint.attractions(latitude: place.latitude, longitude: place.longitude),
                                      ttl: TTL.attractions, forceRefresh: forceRefresh) {
            AttractionRanker.rank(try Decoding.attractions(from: $0, near: origin), excludingTitle: place.name)
        }
    }
}
