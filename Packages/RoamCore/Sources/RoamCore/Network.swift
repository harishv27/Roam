import Foundation

public enum APIError: Error, Equatable {
    /// No connection at all (airplane mode, no signal). Retrying straight away cannot help.
    case offline
    case timeout
    /// The connection dropped mid-request or could not be made. Worth another try.
    case connection
    case http(status: Int, retryAfter: TimeInterval?)
    case invalidResponse
    case decoding(String)

    /// Whether another attempt could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .timeout, .connection: return true
        case .http(let status, _): return status == 408 || status == 429 || (500...599).contains(status)
        case .offline, .invalidResponse, .decoding: return false
        }
    }

    /// A sentence for the screen.
    public var message: String {
        switch self {
        case .offline: return "You're offline."
        case .timeout: return "The server took too long to answer."
        case .connection: return "The connection dropped."
        case .http(let status, _): return status == 429 ? "Too many requests. Try again in a moment." : "The server had a problem (\(status))."
        case .invalidResponse: return "The server sent something unexpected."
        case .decoding: return "The data could not be read."
        }
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real client. Turns every failure into an `APIError`, so nothing above this layer sees `URLError`.
public struct URLSessionClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: throw APIError.offline
            case .timedOut: throw APIError.timeout
            default: throw APIError.connection
            }
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init))
        }
        return (data, http)
    }
}

public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval

    public init(maxRetries: Int = 2, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 8) {
        self.maxRetries = maxRetries; self.baseDelay = baseDelay; self.maxDelay = maxDelay
    }

    /// Exponential backoff (0.5s, 1s, 2s ...), or the server's own `Retry-After`, never longer than `maxDelay`.
    public func delay(forAttempt attempt: Int, error: APIError) -> TimeInterval {
        if case .http(_, let retryAfter?) = error { return min(maxDelay, max(0, retryAfter)) }
        return min(maxDelay, baseDelay * pow(2, Double(attempt)))
    }
}

/// Wraps another client and retries failures that are worth retrying. `sleep` is injected so tests do not wait.
public struct RetryingClient: HTTPClient {
    private let base: HTTPClient
    private let policy: RetryPolicy
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(_ base: HTTPClient, policy: RetryPolicy = RetryPolicy(),
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.base = base; self.policy = policy; self.sleep = sleep
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            do {
                return try await base.send(request)
            } catch let error as APIError where error.isRetryable && attempt < policy.maxRetries {
                try await sleep(policy.delay(forAttempt: attempt, error: error))
                attempt += 1
            }
        }
    }
}
