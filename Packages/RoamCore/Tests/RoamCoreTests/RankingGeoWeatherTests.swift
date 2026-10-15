import XCTest
@testable import RoamCore

final class RankingGeoWeatherTests: XCTestCase {
    private func attraction(_ id: Int, _ title: String, blurb: String? = "Landmark in Lisbon", photo: Bool = true,
                            summary: String = String(repeating: "x", count: 150), meters: Double = 500) -> Attraction {
        Attraction(id: id, title: title, blurb: blurb, summary: summary, latitude: 0, longitude: 0,
                   thumbnailURL: photo ? URL(string: "https://example.com/\(id).jpg") : nil, distanceMeters: meters)
    }

    // MARK: Ranking

    func testRealResponseDropsHistoryAndInstitutions() throws {
        let items = try Decoding.attractions(from: fixture("wikipedia-nearby-lisbon"), near: (lisbon.latitude, lisbon.longitude))
        let titles = AttractionRanker.rank(items).map(\.title)
        XCTAssertFalse(titles.contains("Taifa of Lisbon"))                 // "Medieval emirate"
        XCTAssertFalse(titles.isEmpty)
    }

    func testPhotoAndDescriptionBeatDistance() {
        let near = attraction(1, "Near, no photo", blurb: nil, photo: false, meters: 50)
        let far = attraction(2, "Far, with photo", meters: 4000)
        XCTAssertEqual(AttractionRanker.rank([near, far]).map(\.title), ["Far, with photo", "Near, no photo"])
    }

    func testEqualScoresGoNearestFirst() {
        let a = attraction(1, "A", meters: 900), b = attraction(2, "B", meters: 100), c = attraction(3, "C", meters: 400)
        XCTAssertEqual(AttractionRanker.rank([a, b, c]).map(\.title), ["B", "C", "A"])
    }

    func testPeopleAndAbstractionsAreFilteredButPagesWithoutADescriptionStay() {
        let castle = attraction(1, "Castle", blurb: "Medieval castle")
        let mayor = attraction(2, "Mayor", blurb: "Portuguese politician")
        let kingdom = attraction(3, "Kingdom", blurb: "Medieval Islamic kingdom")
        let unlabeled = attraction(4, "Unlabeled", blurb: nil)
        XCTAssertEqual(Set(AttractionRanker.rank([castle, mayor, kingdom, unlabeled]).map(\.title)), ["Castle", "Unlabeled"])
    }

    func testThePlacesOwnArticleIsLeftOut() {
        let city = attraction(1, "Lisbon", blurb: "Capital of Portugal", meters: 30)
        let tower = attraction(2, "Belém Tower", blurb: "Fortified tower")
        XCTAssertEqual(AttractionRanker.rank([city, tower], excludingTitle: "lisbon").map(\.title), ["Belém Tower"])
        XCTAssertEqual(AttractionRanker.rank([city, tower]).count, 2)
    }

    func testInstitutionsAreFilteredButMuseumsStay() {
        let institute = attraction(1, "Instituto Camões", blurb: "Portuguese international institution")
        let agency = attraction(2, "Some Agency", blurb: "Government agency")
        let museum = attraction(3, "Gulbenkian Museum", blurb: "Art museum in Lisbon")
        XCTAssertEqual(AttractionRanker.rank([institute, agency, museum]).map(\.title), ["Gulbenkian Museum"])
    }

    func testDuplicatesAndTheLimit() {
        let items = (1...30).map { attraction($0, "P\($0)", meters: Double($0)) } + [attraction(1, "Dup")]
        let ranked = AttractionRanker.rank(items, limit: 5)
        XCTAssertEqual(ranked.count, 5)
        XCTAssertEqual(Set(ranked.map(\.id)).count, 5)
        XCTAssertEqual(ranked.first?.title, "P1")
    }

    // MARK: Geo

    func testDistanceLisbonToPorto() {
        let d = Geo.distance(lat1: 38.7223, lon1: -9.1393, lat2: 41.1579, lon2: -8.6291)
        XCTAssertEqual(d / 1000, 274, accuracy: 3)
        XCTAssertEqual(Geo.distance(lat1: 10, lon1: 10, lat2: 10, lon2: 10), 0, accuracy: 0.001)
    }

    func testDistanceFormatting() {
        XCTAssertEqual(Geo.format(meters: 347, metric: true), "350 m")
        XCTAssertEqual(Geo.format(meters: 1234, metric: true), "1.2 km")
        XCTAssertEqual(Geo.format(meters: 15_400, metric: true), "15 km")
        XCTAssertEqual(Geo.format(meters: 60, metric: false), "200 ft")
        XCTAssertEqual(Geo.format(meters: 1609, metric: false), "1.0 mi")
        XCTAssertEqual(Geo.format(meters: 40_000, metric: false), "25 mi")
    }

    // MARK: Weather

    func testWeatherCodes() {
        XCTAssertEqual(WeatherCode.description(0), "Clear")
        XCTAssertEqual(WeatherCode.description(63), "Rain")
        XCTAssertEqual(WeatherCode.description(95), "Thunderstorm")
        XCTAssertEqual(WeatherCode.description(1234), "Unknown")
        XCTAssertEqual(WeatherCode.symbol(0, isDay: true), "sun.max.fill")
        XCTAssertEqual(WeatherCode.symbol(0, isDay: false), "moon.stars.fill")
        XCTAssertEqual(WeatherCode.symbol(2, isDay: false), "cloud.moon.fill")
        XCTAssertEqual(WeatherCode.symbol(75), "cloud.snow.fill")
    }

    func testEveryDocumentedCodeHasAWordAndASymbol() {
        for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
            XCTAssertNotEqual(WeatherCode.description(code), "Unknown", "code \(code)")
            XCTAssertNotEqual(WeatherCode.symbol(code), "questionmark.circle", "code \(code)")
        }
    }

    // MARK: Endpoints

    func testSearchURLIsEncodedAndStable() throws {
        let request = Endpoint.searchPlaces(query: "São Paulo")
        let url = try XCTUnwrap(request.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://geocoding-api.open-meteo.com/v1/search?"))
        XCTAssertTrue(url.contains("name=S%C3%A3o%20Paulo"))
        XCTAssertEqual(url, Endpoint.searchPlaces(query: "São Paulo").url?.absoluteString)    // same request, same cache key
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), Endpoint.userAgent)
    }

    func testQueryCharactersCannotInjectParameters() throws {
        let url = try XCTUnwrap(Endpoint.searchPlaces(query: "a&count=1000#x").url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "count" }?.value, "10")
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "a&count=1000#x")
    }

    func testForecastAndAttractionRequests() throws {
        let forecast = try XCTUnwrap(Endpoint.forecast(latitude: 38.72509, longitude: -9.1498).url?.absoluteString)
        XCTAssertTrue(forecast.contains("latitude=38.7251"))
        XCTAssertTrue(forecast.contains("longitude=-9.1498"))
        XCTAssertTrue(forecast.contains("forecast_days=7"))

        let wiki = try XCTUnwrap(URLComponents(url: Endpoint.attractions(latitude: 1, longitude: 2, radiusMeters: 99_999, limit: 500).url!, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (wiki.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["ggsradius"], "10000")        // the API's maximum
        XCTAssertEqual(items["ggslimit"], "50")
        XCTAssertEqual(items["ggscoord"], "1.0000|2.0000")
    }
}
