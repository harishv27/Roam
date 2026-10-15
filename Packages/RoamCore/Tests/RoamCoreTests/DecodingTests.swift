import XCTest
@testable import RoamCore

final class DecodingTests: XCTestCase {
    // MARK: Places

    func testRealGeocodingResponse() throws {
        let places = try Decoding.places(from: fixture("geocoding-lisbon"))
        XCTAssertEqual(places.count, 3)
        let first = places[0]
        XCTAssertEqual(first.name, "Lisbon")
        XCTAssertEqual(first.country, "Portugal")
        XCTAssertEqual(first.countryCode, "PT")
        XCTAssertEqual(first.region, "Lisbon District")
        XCTAssertEqual(first.latitude, 38.72509, accuracy: 0.0001)
        XCTAssertEqual(first.timezone, "Europe/Lisbon")
        XCTAssertEqual(first.population, 517802)
        XCTAssertEqual(places[1].countryCode, "US")
    }

    func testNoMatchesAreAnEmptyListNotAnError() throws {
        XCTAssertEqual(try Decoding.places(from: Data(#"{"generationtime_ms":0.5}"#.utf8)), [])
    }

    func testAPlaceMissingOptionalFieldsStillDecodes() throws {
        let json = #"{"results":[{"id":1,"name":"Nowhere","latitude":1.5,"longitude":2.5}]}"#
        let place = try XCTUnwrap(Decoding.places(from: Data(json.utf8)).first)
        XCTAssertEqual(place.country, "")
        XCTAssertNil(place.region)
        XCTAssertNil(place.population)
        XCTAssertEqual(place.flag, "")
    }

    func testGarbageIsADecodingError() {
        XCTAssertThrowsError(try Decoding.places(from: Data("<html>".utf8))) { error in
            guard case APIError.decoding = error else { return XCTFail("\(error)") }
        }
        XCTAssertThrowsError(try Decoding.forecast(from: Data("{}".utf8)))
    }

    func testFlagAndSubtitle() {
        XCTAssertEqual(lisbon.flag, "🇵🇹")
        XCTAssertEqual(lisbon.subtitle, "Lisbon District, Portugal")
        let singapore = Place(id: 2, name: "Singapore", country: "Singapore", countryCode: "sg", region: "Singapore", latitude: 1.29, longitude: 103.85)
        XCTAssertEqual(singapore.flag, "🇸🇬")
        XCTAssertEqual(singapore.subtitle, "Singapore")        // the region repeats the name
        XCTAssertEqual(Place(id: 3, name: "X", country: "Y", countryCode: "1?", latitude: 0, longitude: 0).flag, "")
    }

    // MARK: Forecast

    func testRealForecastResponse() throws {
        let forecast = try Decoding.forecast(from: fixture("forecast-lisbon"))
        XCTAssertEqual(forecast.timezone, "Europe/Lisbon")
        XCTAssertEqual(forecast.current.temperatureC, 24.5)
        XCTAssertEqual(forecast.current.weatherCode, 0)
        XCTAssertEqual(forecast.current.windKph, 4.2)
        XCTAssertTrue(forecast.current.isDay)
        XCTAssertEqual(forecast.days.count, 7)
        XCTAssertEqual(forecast.days[0].date, "2026-10-14")
        XCTAssertEqual(forecast.days[0].highC, 31.3)
        XCTAssertEqual(forecast.days[0].lowC, 15.7)
        XCTAssertEqual(forecast.days[0].rainChance, 0)
    }

    func testNullsInTheDailyArraysDropThatDay() throws {
        let json = """
        {"timezone":"UTC","current":{"temperature_2m":10,"weather_code":3},
         "daily":{"time":["2026-01-01","2026-01-02","2026-01-03"],"weather_code":[1,null,2],
                  "temperature_2m_max":[5.0,6.0,null],"temperature_2m_min":[1.0,2.0,3.0],
                  "precipitation_probability_max":[10,null,30]}}
        """
        let forecast = try Decoding.forecast(from: Data(json.utf8))
        XCTAssertEqual(forecast.days.map(\.date), ["2026-01-01"])    // day 2 has no code, day 3 no high
        XCTAssertEqual(forecast.current.windKph, 0)                  // missing wind defaults
        XCTAssertTrue(forecast.current.isDay)                        // missing is_day defaults to day
    }

    func testShorterParallelArraysDoNotCrash() throws {
        let json = """
        {"timezone":"UTC","current":{"temperature_2m":10,"weather_code":3,"is_day":0},
         "daily":{"time":["2026-01-01","2026-01-02"],"weather_code":[1],"temperature_2m_max":[5.0],"temperature_2m_min":[1.0]}}
        """
        let forecast = try Decoding.forecast(from: Data(json.utf8))
        XCTAssertEqual(forecast.days.count, 1)
        XCTAssertNil(forecast.days[0].rainChance)
        XCTAssertFalse(forecast.current.isDay)
    }

    // MARK: Attractions

    func testRealWikipediaResponse() throws {
        let origin = (latitude: lisbon.latitude, longitude: lisbon.longitude)
        let items = try Decoding.attractions(from: fixture("wikipedia-nearby-lisbon"), near: origin)
        XCTAssertEqual(items.count, 5)
        let academy = try XCTUnwrap(items.first { $0.title == "Military Academy (Portugal)" })
        XCTAssertNotNil(academy.thumbnailURL)
        XCTAssertNil(academy.blurb)
        XCTAssertTrue(academy.summary.hasPrefix("The Military Academy"))
        XCTAssertEqual(academy.distanceMeters, 1000, accuracy: 700)
        XCTAssertEqual(academy.pageURL.absoluteString, "https://en.wikipedia.org/?curid=2127202")
    }

    func testNothingNearbyIsEmpty() throws {
        XCTAssertEqual(try Decoding.attractions(from: Data(#"{"batchcomplete":true}"#.utf8), near: (0, 0)), [])
    }

    func testPagesWithoutCoordinatesAreDropped() throws {
        let json = #"{"query":{"pages":[{"pageid":1,"title":"A"},{"pageid":2,"title":"B","coordinates":[{"lat":1,"lon":2}]}]}}"#
        XCTAssertEqual(try Decoding.attractions(from: Data(json.utf8), near: (1, 2)).map(\.title), ["B"])
    }
}
