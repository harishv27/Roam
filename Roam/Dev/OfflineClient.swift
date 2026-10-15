import Foundation
import RoamCore

#if DEBUG
/// `-simulateOffline` makes every request fail the way airplane mode does, to try the cached paths.
struct OfflineClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw APIError.offline }
}
#endif
