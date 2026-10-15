import Foundation
@testable import RoamCore

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}

func response(_ request: URLRequest, status: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
}

/// A client that answers from a closure and counts what it was asked.
final class MockClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    var handler: @Sendable (URLRequest) throws -> Data

    init(_ handler: @escaping @Sendable (URLRequest) throws -> Data) { self.handler = handler }

    var requests: [URLRequest] { lock.withLock { _requests } }
    var count: Int { requests.count }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { _requests.append(request) }
        let data = try handler(request)
        return (data, response(request))
    }
}

/// Fails with the given errors in order, then succeeds.
final class FlakyClient: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var failures: [Error]
    private(set) var attempts = 0

    init(failures: [Error]) { self.failures = failures }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let next: Error? = lock.withLock {
            attempts += 1
            return failures.isEmpty ? nil : failures.removeFirst()
        }
        if let next { throw next }
        return (Data("ok".utf8), response(request))
    }
}

final class Delays: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []
    func add(_ value: TimeInterval) { lock.withLock { values.append(value) } }
    var all: [TimeInterval] { lock.withLock { values } }
}

/// A clock the test moves by hand.
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

let lisbon = Place(id: 2267057, name: "Lisbon", country: "Portugal", countryCode: "PT", region: "Lisbon District",
                   latitude: 38.72509, longitude: -9.1498, timezone: "Europe/Lisbon", population: 517802)
