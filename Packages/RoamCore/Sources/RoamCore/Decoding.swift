import Foundation

/// Turns the three APIs' JSON into the app's own models. The wire formats are private to this file: if an API changes,
/// only these structs change.
public enum Decoding {
    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw APIError.decoding(String(describing: error).prefix(160).description)
        }
    }

    // MARK: Geocoding

    private struct GeocodingResponse: Decodable {
        struct Item: Decodable {
            let id: Int
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let country_code: String?
            let admin1: String?
            let timezone: String?
            let population: Int?
        }
        let results: [Item]?          // absent, not empty, when nothing matches
    }

    public static func places(from data: Data) throws -> [Place] {
        try decode(GeocodingResponse.self, from: data).results?.map {
            Place(id: $0.id, name: $0.name, country: $0.country ?? "", countryCode: $0.country_code ?? "",
                  region: $0.admin1, latitude: $0.latitude, longitude: $0.longitude, timezone: $0.timezone,
                  population: $0.population)
        } ?? []
    }

    // MARK: Forecast

    private struct ForecastResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let wind_speed_10m: Double?
            let is_day: Int?
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]?
        }
        let timezone: String
        let current: Current
        let daily: Daily
    }

    public static func forecast(from data: Data) throws -> Forecast {
        let response = try decode(ForecastResponse.self, from: data)
        let daily = response.daily
        // The arrays are parallel and may hold nulls (the model has no value yet); a day without a code or both
        // temperatures is dropped rather than shown as zeros.
        let days: [DayForecast] = daily.time.enumerated().compactMap { index, date in
            guard index < daily.weather_code.count, let code = daily.weather_code[index],
                  index < daily.temperature_2m_max.count, let high = daily.temperature_2m_max[index],
                  index < daily.temperature_2m_min.count, let low = daily.temperature_2m_min[index] else { return nil }
            let rain = daily.precipitation_probability_max.flatMap { index < $0.count ? $0[index] : nil }
            return DayForecast(date: date, weatherCode: code, highC: high, lowC: low, rainChance: rain)
        }
        let c = response.current
        return Forecast(current: CurrentWeather(temperatureC: c.temperature_2m, weatherCode: c.weather_code,
                                                windKph: c.wind_speed_10m ?? 0, isDay: (c.is_day ?? 1) == 1),
                        days: days, timezone: response.timezone)
    }

    // MARK: Wikipedia

    private struct WikiResponse: Decodable {
        struct Page: Decodable {
            struct Coordinates: Decodable { let lat: Double; let lon: Double }
            struct Thumbnail: Decodable { let source: String }
            let pageid: Int
            let title: String
            let coordinates: [Coordinates]?
            let thumbnail: Thumbnail?
            let description: String?
            let extract: String?
        }
        struct Query: Decodable { let pages: [Page]? }
        let query: Query?             // absent when nothing is nearby
    }

    /// Pages near `origin`, with the distance worked out from their own coordinates. Pages without coordinates are
    /// dropped. Wikipedia's own ordering is not used; see `AttractionRanker`.
    public static func attractions(from data: Data, near origin: (latitude: Double, longitude: Double)) throws -> [Attraction] {
        try decode(WikiResponse.self, from: data).query?.pages?.compactMap { page in
            guard let point = page.coordinates?.first else { return nil }
            return Attraction(
                id: page.pageid, title: page.title,
                blurb: page.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                summary: (page.extract ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                latitude: point.lat, longitude: point.lon,
                thumbnailURL: page.thumbnail.flatMap { URL(string: $0.source) },
                distanceMeters: Geo.distance(lat1: origin.latitude, lon1: origin.longitude, lat2: point.lat, lon2: point.lon))
        } ?? []
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
