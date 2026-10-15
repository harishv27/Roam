import Foundation
import SwiftData
import RoamCore

/// A place the user saved. Only the place itself is stored: its forecast and landmarks are read from the response
/// cache, which is why a saved place still opens offline (as long as it was opened once while online).
@Model
final class SavedPlace {
    @Attribute(.unique) var placeID: Int = 0
    var name: String = ""
    var country: String = ""
    var countryCode: String = ""
    var region: String?
    var latitude: Double = 0
    var longitude: Double = 0
    var timezone: String?
    var population: Int?
    var savedAt: Date = Date.now

    init(_ place: Place) {
        placeID = place.id
        name = place.name
        country = place.country
        countryCode = place.countryCode
        region = place.region
        latitude = place.latitude
        longitude = place.longitude
        timezone = place.timezone
        population = place.population
    }

    var place: Place {
        Place(id: placeID, name: name, country: country, countryCode: countryCode, region: region,
              latitude: latitude, longitude: longitude, timezone: timezone, population: population)
    }
}
