import Foundation
import Observation
import RoamCore

/// The last places opened, newest first, kept in UserDefaults.
@MainActor
@Observable
final class RecentPlaces {
    private static let key = "recentPlaces"
    private(set) var places: [Place]

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        places = data.flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
    }

    func add(_ place: Place) {
        places.removeAll { $0.id == place.id }
        places.insert(place, at: 0)
        places = Array(places.prefix(8))
        UserDefaults.standard.set(try? JSONEncoder().encode(places), forKey: Self.key)
    }

    func clear() {
        places = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}
