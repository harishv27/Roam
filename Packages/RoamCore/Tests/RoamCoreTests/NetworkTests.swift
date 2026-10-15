import XCTest
@testable import RoamCore

final class NetworkTests: XCTestCase {
    private let request = URLRequest(url: URL(string: "https://example.com/a")!)

    // MARK: Error policy

    func testWhichErrorsAreWorthRetrying() {
        XCTAssertTrue(APIError.timeout.isRetryable)
        XCTAssertTrue(APIError.connection.isRetryable)
        XCTAssertTrue(APIError.http(status: 500, retryAfter: nil).isRetryable)
        XCTAssertTrue(APIError.http(status: 503, retryAfter: nil).isRetryable)
        XCTAssertTrue(APIError.http(status: 429, retryAfter: nil).isRetryable)
        XCTAssertTrue(APIError.http(status: 408, retryAfter: nil).isRetryable)
        XCTAssertFalse(APIError.http(status: 404, retryAfter: nil).isRetryable)
        XCTAssertFalse(APIError.http(status: 400, retryAfter: nil).isRetryable)
        XCTAssertFalse(APIError.offline.isRetryable)
        XCTAssertFalse(APIError.decoding("x").isRetryable)
        XCTAssertFalse(APIError.invalidResponse.isRetryable)
    }

    func testBackoffDoublesAndIsCapped() {
        let policy = RetryPolicy(maxRetries: 5, baseDelay: 0.5, maxDelay: 3)
        let error = APIError.timeout
        XCTAssertEqual([0, 1, 2, 3, 4].map { policy.delay(forAttempt: $0, error: error) }, [0.5, 1, 2, 3, 3])
    }

    func testRetryAfterOverridesBackoffButIsCapped() {
        let policy = RetryPolicy(maxRetries: 2, baseDelay: 0.5, maxDelay: 8)
        XCTAssertEqual(policy.delay(forAttempt: 0, error: .http(status: 429, retryAfter: 3)), 3)
        XCTAssertEqual(policy.delay(forAttempt: 0, error: .http(status: 429, retryAfter: 600)), 8)
    }

    // MARK: Retrying client

    func testSucceedsAfterTransientFailures() async throws {
        let flaky = FlakyClient(failures: [APIError.timeout, APIError.http(status: 503, retryAfter: nil)])
        let delays = Delays()
        let client = RetryingClient(flaky, policy: RetryPolicy(maxRetries: 2, baseDelay: 1, maxDelay: 10)) { delays.add($0) }
        let (data, _) = try await client.send(request)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(flaky.attempts, 3)
        XCTAssertEqual(delays.all, [1, 2])
    }

    func testGivesUpAfterTheLimit() async {
        let flaky = FlakyClient(failures: Array(repeating: APIError.connection, count: 10))
        let client = RetryingClient(flaky, policy: RetryPolicy(maxRetries: 2)) { _ in }
        do { _ = try await client.send(request); XCTFail("should throw") } catch {
            XCTAssertEqual(error as? APIError, .connection)
        }
        XCTAssertEqual(flaky.attempts, 3)          // the first try plus two retries
    }

    func testPermanentFailuresAreNotRetried() async {
        for error in [APIError.offline, .http(status: 404, retryAfter: nil), .decoding("x")] {
            let flaky = FlakyClient(failures: [error])
            let client = RetryingClient(flaky) { _ in XCTFail("should not wait") }
            do { _ = try await client.send(request); XCTFail("should throw") } catch {}
            XCTAssertEqual(flaky.attempts, 1, "\(error)")
        }
    }

    func testAServersRetryAfterIsHonoured() async throws {
        let flaky = FlakyClient(failures: [APIError.http(status: 429, retryAfter: 4)])
        let delays = Delays()
        _ = try await RetryingClient(flaky) { delays.add($0) }.send(request)
        XCTAssertEqual(delays.all, [4])
    }

    func testCancellationWhileWaitingStopsTheRetries() async {
        let flaky = FlakyClient(failures: Array(repeating: APIError.timeout, count: 5))
        let client = RetryingClient(flaky) { _ in throw CancellationError() }
        do { _ = try await client.send(request); XCTFail("should throw") } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(flaky.attempts, 1)
    }

    // MARK: URLSession client (with a stubbed protocol, no real network)

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testStatusCodesBecomeErrors() async throws {
        let client = URLSessionClient(session: stubbedSession())
        StubProtocol.handler = { _ in (200, [:], Data("hi".utf8), nil) }
        let (data, http) = try await client.send(request)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hi")
        XCTAssertEqual(http.statusCode, 200)

        StubProtocol.handler = { _ in (429, ["Retry-After": "7"], Data(), nil) }
        do { _ = try await client.send(request); XCTFail("should throw") } catch {
            XCTAssertEqual(error as? APIError, .http(status: 429, retryAfter: 7))
        }
        StubProtocol.handler = { _ in (404, [:], Data(), nil) }
        do { _ = try await client.send(request); XCTFail("should throw") } catch {
            XCTAssertEqual(error as? APIError, .http(status: 404, retryAfter: nil))
        }
    }

    func testURLErrorsAreMapped() async {
        let client = URLSessionClient(session: stubbedSession())
        let table: [(URLError.Code, APIError)] = [(.notConnectedToInternet, .offline), (.timedOut, .timeout),
                                                   (.networkConnectionLost, .connection), (.cannotFindHost, .connection)]
        for (code, expected) in table {
            StubProtocol.handler = { _ in (0, [:], Data(), URLError(code)) }
            do { _ = try await client.send(request); XCTFail("should throw") } catch {
                XCTAssertEqual(error as? APIError, expected, "\(code)")
            }
        }
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data, Error?))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (status, headers, data, error) = handler(request)
        if let error { client?.urlProtocol(self, didFailWithError: error); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
