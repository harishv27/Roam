import Foundation

/// A city or town from the geocoder.
public struct Place: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let country: String
    public let countryCode: String
    /// State, province or district ("Ohio", "Lisbon District").
    public let region: String?
    public let latitude: Double
    public let longitude: Double
    public let timezone: String?
    public let population: Int?

    public init(id: Int, name: String, country: String, countryCode: String, region: String? = nil,
                latitude: Double, longitude: Double, timezone: String? = nil, population: Int? = nil) {
        self.id = id; self.name = name; self.country = country; self.countryCode = countryCode; self.region = region
        self.latitude = latitude; self.longitude = longitude; self.timezone = timezone; self.population = population
    }

    /// "Lisbon District, Portugal", or just the country when the region repeats the name.
    public var subtitle: String {
        if let region, !region.isEmpty, region != name { return "\(region), \(country)" }
        return country
    }

    /// The country's flag as an emoji, built from its two-letter code. Empty for anything that is not a valid code.
    public var flag: String {
        let code = countryCode.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy({ $0.value >= 65 && $0.value <= 90 }) else { return "" }
        return String(code.unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }.map(Character.init))
    }
}

public struct CurrentWeather: Codable, Equatable, Sendable {
    public let temperatureC: Double
    public let weatherCode: Int
    public let windKph: Double
    public let isDay: Bool
}

public struct DayForecast: Codable, Equatable, Identifiable, Sendable {
    public var id: String { date }
    /// Local date at the place, "2026-10-14".
    public let date: String
    public let weatherCode: Int
    public let highC: Double
    public let lowC: Double
    /// Chance of rain, 0...100, when the model provides it.
    public let rainChance: Int?
}

public struct Forecast: Codable, Equatable, Sendable {
    public let current: CurrentWeather
    public let days: [DayForecast]
    public let timezone: String
}

/// A nearby point of interest, from Wikipedia's geosearch.
public struct Attraction: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let title: String
    /// Wikipedia's one-line description ("Medieval castle in Lisbon").
    public let blurb: String?
    public let summary: String
    public let latitude: Double
    public let longitude: Double
    public let thumbnailURL: URL?
    public let distanceMeters: Double

    public var pageURL: URL { URL(string: "https://en.wikipedia.org/?curid=\(id)")! }
}
