import Foundation

/// The three requests the app makes, built with `URLComponents` so every value is percent-encoded properly.
/// No API key is needed for any of them.
public enum Endpoint {
    /// Wikipedia asks API clients to say who they are.
    public static let userAgent = "Roam/1.0 (iOS portfolio app; https://github.com/harishv27)"

    public static func searchPlaces(query: String, count: Int = 10, language: String = "en") -> URLRequest {
        make("geocoding-api.open-meteo.com", "/v1/search", [
            "name": query, "count": String(count), "language": language, "format": "json",
        ])
    }

    public static func forecast(latitude: Double, longitude: Double, days: Int = 7) -> URLRequest {
        make("api.open-meteo.com", "/v1/forecast", [
            "latitude": coordinate(latitude), "longitude": coordinate(longitude),
            "current": "temperature_2m,weather_code,wind_speed_10m,is_day",
            "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
            "timezone": "auto", "forecast_days": String(days),
        ])
    }

    /// Wikipedia pages near a point, with thumbnail, one-line description and intro in a single request.
    /// The API's maximum radius is 10 km.
    public static func attractions(latitude: Double, longitude: Double, radiusMeters: Int = 10_000, limit: Int = 30) -> URLRequest {
        make("en.wikipedia.org", "/w/api.php", [
            "action": "query", "format": "json", "formatversion": "2",
            "generator": "geosearch", "ggscoord": "\(coordinate(latitude))|\(coordinate(longitude))",
            "ggsradius": String(min(10_000, max(10, radiusMeters))), "ggslimit": String(min(50, max(1, limit))),
            "prop": "coordinates|pageimages|description|extracts",
            "exintro": "1", "explaintext": "1", "exlimit": "max", "exsentences": "3",
            "piprop": "thumbnail", "pithumbsize": "600", "colimit": "max",
        ])
    }

    /// Five decimal places is about a metre, and keeps equal points on equal URLs so they share a cache entry.
    static func coordinate(_ value: Double) -> String { String(format: "%.4f", value) }

    private static func make(_ host: String, _ path: String, _ items: [String: String]) -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        // Sorted, so the same request always produces the same URL (and the same cache key).
        components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
