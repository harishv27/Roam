import Foundation
import Observation
import RoamCore

@MainActor
@Observable
final class SearchModel {
    enum State {
        case idle
        case loading
        case results([Place], stale: Bool)
        case empty
        case failed(String)
    }

    var state = State.idle

    func search(_ query: String, using service: RoamService) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { state = .idle; return }
        state = .loading
        do {
            let loaded = try await service.searchPlaces(text)
            if Task.isCancelled { return }                  // a newer query took over
            state = loaded.value.isEmpty ? .empty : .results(loaded.value, stale: loaded.isStale)
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            state = .failed((error as? APIError)?.message ?? "Something went wrong.")
        }
    }
}
