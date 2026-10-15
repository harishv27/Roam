import Foundation
import Observation
import RoamCore

@MainActor
@Observable
final class PlaceDetailModel {
    let place: Place
    private let service: RoamService

    var forecast: Loaded<Forecast>?
    var attractions: Loaded<[Attraction]>?
    var forecastError: String?
    var attractionsError: String?
    var isLoading = false

    init(place: Place, service: RoamService) {
        self.place = place
        self.service = service
    }

    /// The oldest age among the pieces showing saved data, or nil when everything is live.
    var staleAge: TimeInterval? {
        var ages: [TimeInterval] = []
        if case .cache(let age, true)? = forecast?.source { ages.append(age) }
        if case .cache(let age, true)? = attractions?.source { ages.append(age) }
        return ages.max()
    }

    func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        async let forecastResult = result { try await self.service.forecast(for: self.place, forceRefresh: force) }
        async let attractionsResult = result { try await self.service.attractions(near: self.place, forceRefresh: force) }
        let (f, a) = await (forecastResult, attractionsResult)
        if Task.isCancelled { return }
        switch f {
        case .success(let value): forecast = value; forecastError = nil
        case .failure(let error): if forecast == nil { forecastError = Self.message(error) }
        }
        switch a {
        case .success(let value): attractions = value; attractionsError = nil
        case .failure(let error): if attractions == nil { attractionsError = Self.message(error) }
        }
    }

    private func result<T>(_ work: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    private static func message(_ error: Error) -> String { (error as? APIError)?.message ?? "Something went wrong." }
}
