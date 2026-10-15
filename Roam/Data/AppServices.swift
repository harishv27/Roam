import Foundation
import Observation
import RoamCore

/// Builds the networking stack once: URLSession, wrapped in retries, with the response cache behind it.
@MainActor
@Observable
final class AppServices {
    let service: RoamService
    let recents = RecentPlaces()

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cache = DiskCache(directory: caches.appendingPathComponent("RoamAPI", isDirectory: true))
        cache.prune(olderThan: 30 * 86_400)

        // Wikipedia thumbnails go through the normal URL cache, with room for a few hundred of them.
        URLCache.shared = URLCache(memoryCapacity: 20 * 1_024 * 1_024, diskCapacity: 150 * 1_024 * 1_024)

        var client: HTTPClient = RetryingClient(URLSessionClient())
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulateOffline") { client = OfflineClient() }
        #endif
        service = RoamService(client: client, cache: cache)
    }
}
