package import Foundation
import FoundationModels
import LanguageModelsCore

// MARK: - Client

/// Sends a provider's HTTP requests: with the package's `User-Agent`, following redirects only to the same host, and
/// sending a request that fails again as the provider's ``RetryPolicy`` says.
///
/// A request is sent again only before any of its response is read: after a failed connection or a response that the
/// policy retries. A response that asks for a longer wait than the policy allows fails the request at once instead,
/// with the wait on its error, so the app can retry later, and so does one that the policy doesn't retry, such as one
/// whose `x-should-retry` is `false`.
struct HTTPClient: Sendable {
    /// The decoder of response bodies and streamed chunks, which requests share, since `JSONDecoder` is `Sendable`.
    static let decoder = JSONDecoder()

    private let session: URLSession

    /// When a request that fails is sent again, and how long it waits first.
    private let retryPolicy: RetryPolicy

    /// The most bytes of a failed response's body to read, which holds its error.
    private let errorBodyLimit = 1 << 20

    /// Creates a client that sends a request that fails again as a policy says.
    ///
    /// - Parameters:
    ///   - session: The URL session that sends the requests.
    ///   - retryPolicy: When a request that fails is sent again, and how long it waits first.
    init(session: URLSession, retryPolicy: RetryPolicy) {
        self.session = session
        self.retryPolicy = retryPolicy
    }

    /// A response whose status isn't a success, with the start of its body and the delay it asks to wait.
    struct Failure: Error {
        /// The HTTP status, or 0 for a response that isn't HTTP.
        let status: Int
        let body: Data
        let response: HTTPURLResponse?

        /// The wait the response's `retry-after-ms` or `Retry-After` header asks for.
        var retryAfter: Duration? {
            HTTPClient.retryAfter(of: response)
        }
    }

    /// A request with the authentication's headers, then the given headers, then the package's `User-Agent` and the
    /// content types, each taking precedence over a header of the same name before it.
    ///
    /// - Parameters:
    ///   - url: Where the request goes.
    ///   - method: The HTTP method, such as `POST`.
    ///   - body: The JSON body, or `nil` for none.
    ///   - accept: The `Accept` header, such as `text/event-stream`.
    ///   - authHeaders: The headers that authenticate the request.
    ///   - headers: The provider's own headers.
    ///   - idleTimeout: How long to wait for the next data, or `nil` for the session's default.
    /// - Returns: The request.
    static func request(
        url: URL,
        method: String = HTTPMethod.get,
        body: Data? = nil,
        accept: String = MediaType.json,
        authHeaders: [HTTPHeaderName: String],
        headers: [HTTPHeaderName: String] = [:],
        idleTimeout: Duration? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (name, value) in authHeaders.merging(headers, uniquingKeysWith: { $1 }) {
            request.setValue(value, forHTTPHeaderField: name.rawValue)
        }
        if body != nil { request.setValue(MediaType.json, forHTTPHeaderField: HTTPHeaderName.contentType.rawValue) }
        request.setValue(accept, forHTTPHeaderField: HTTPHeaderName.accept.rawValue)
        request.setValue(UserAgent.current, forHTTPHeaderField: HTTPHeaderName.userAgent.rawValue)
        if let idleTimeout { request.timeoutInterval = idleTimeout / .seconds(1) }
        return request
    }

    /// Opens a response stream.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - onRetry: Called with each retry before its wait, such as to log it.
    /// - Returns: The stream and its response's headers.
    /// - Throws: ``Failure`` for a status that isn't a success, after the retries; and what a session's request throws,
    ///   with a `URLError` mapped the way a failed connection's is.
    func stream(for request: URLRequest, onRetry: (Retry) -> Void = { _ in }) async throws -> (
        URLSession.AsyncBytes, ResponseHeaders
    ) {
        let (bytes, response) = try await send(
            request, onRetry: onRetry, load: { try await session.bytes(for: $0, delegate: SameHostRedirects()) },
            discard: { $0.task.cancel() },
            errorBody: { bytes in
                let body = try await prefix(of: bytes)
                // A body longer than the limit would otherwise keep downloading.
                bytes.task.cancel()
                return body
            })
        return (bytes, ResponseHeaders(response))
    }

    /// Reads a response's body.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - onRetry: Called with each retry before its wait, such as to log it.
    /// - Returns: The body and its response.
    /// - Throws: ``Failure`` for a status that isn't a success, after the retries; and what a session's request throws,
    ///   with a `URLError` mapped the way a failed connection's is.
    func data(for request: URLRequest, onRetry: (Retry) -> Void = { _ in }) async throws -> (Data, HTTPURLResponse?) {
        try await send(
            request, onRetry: onRetry, load: { try await session.data(for: $0, delegate: SameHostRedirects()) },
            discard: { _ in }, errorBody: { $0.prefix(errorBodyLimit) })
    }

    /// Sends a request, and sends it again after the policy's wait for as long as the policy retries what failed.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - onRetry: Called with each retry before its wait.
    ///   - load: Sends the request, returning its content, such as a body or a stream, and its response.
    ///   - discard: Lets go of the content of a response that's retried.
    ///   - errorBody: The start of a failed response's content, which holds its error.
    /// - Returns: The content and its response.
    /// - Throws: ``Failure`` for a status that isn't a success, after the retries; and what `load` throws, with a
    ///   `URLError` mapped the way a failed connection's is.
    private func send<Content>(
        _ request: URLRequest,
        onRetry: (Retry) -> Void,
        load: (URLRequest) async throws -> (Content, URLResponse),
        discard: (Content) -> Void,
        errorBody: (Content) async throws -> Data
    ) async throws -> (Content, HTTPURLResponse?) {
        var retried = 0
        while true {
            let (content, response): (Content, URLResponse)
            do {
                (content, response) = try await load(request)
            } catch let error as URLError {
                guard let retry = retryPolicy.retry(retried + 1, after: error) else {
                    throw error.thrownError
                }
                retried = try await wait(for: retry, onRetry: onRetry)
                continue
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            if (200..<300).contains(status) { return (content, http) }
            guard let retry = retryPolicy.retry(retried + 1, status: status, response: http) else {
                throw Failure(status: status, body: try await errorBody(content), response: http)
            }
            discard(content)
            retried = try await wait(for: retry, onRetry: onRetry)
        }
    }

    /// Reports a retry, then waits for it.
    ///
    /// - Returns: The retry's number, which is how many retries the request has made.
    /// - Throws: `CancellationError` when the task is cancelled during the wait.
    private func wait(for retry: Retry, onRetry: (Retry) -> Void) async throws -> Int {
        onRetry(retry)
        try await Task.sleep(for: retry.wait)
        return retry.number
    }

    /// The wait a response asks for: its `retry-after-ms` header, in milliseconds, or its `Retry-After` header.
    private static func retryAfter(of response: HTTPURLResponse?) -> Duration? {
        Duration(retryAfterMilliseconds: response?.value(forHTTPHeaderField: HTTPHeaderName.retryAfterMilliseconds.rawValue))
            ?? Duration(retryAfter: response?.value(forHTTPHeaderField: HTTPHeaderName.retryAfter.rawValue))
    }

    /// The start of a failed response's body, which holds its error.
    private func prefix(of bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= errorBodyLimit { break }
        }
        return data
    }
}

extension URLError {
    /// The error to throw for a failed connection: cancellation as `CancellationError`, a timeout as
    /// `LanguageModelError.timeout`, and any other failure as the `URLError` itself.
    var thrownError: any Error {
        switch code {
        case .cancelled: CancellationError()
        case .timedOut: LanguageModelError.timeout(.init(debugDescription: localizedDescription))
        default: self
        }
    }
}

// MARK: - Retries

extension HTTPClient {
    /// When a provider's request that fails is sent again, and how long it waits first.
    ///
    /// A connection makes its policy from the app's ``RequestRetries`` with
    /// ``RequestRetries/policy(statuses:)``, giving only the statuses the provider retries.
    struct RetryPolicy: Sendable {
        /// The most times a request is sent again.
        let retries: Int

        /// Whether a response is retried, from its status and its `x-should-retry` header, if any.
        private let retriesResponse: @Sendable (_ status: Int, _ shouldRetry: String?) -> Bool

        /// The wait before a retry, from how many retries came before it and the wait the response asks for, if
        /// any, or `nil` to fail at once.
        private let wait: @Sendable (_ retried: Int, _ asked: Duration?) -> Duration?

        /// Creates a policy.
        ///
        /// - Parameters:
        ///   - retries: The most times a request is sent again.
        ///   - retriesResponse: Whether a response is retried, from its status and its `x-should-retry` header, if
        ///     any.
        ///   - wait: The wait before a retry, from how many retries came before it and the wait the response asks for,
        ///     if any, or `nil` to fail at once.
        private init(
            retries: Int,
            retriesResponse: @escaping @Sendable (_ status: Int, _ shouldRetry: String?) -> Bool,
            wait: @escaping @Sendable (_ retried: Int, _ asked: Duration?) -> Duration?
        ) {
            self.retries = retries
            self.retriesResponse = retriesResponse
            self.wait = wait
        }

        /// The retry of a request whose response failed, or `nil` when the request fails at once.
        ///
        /// - Parameters:
        ///   - number: The retry's number, from 1.
        ///   - status: The response's status.
        ///   - response: The response, whose `x-should-retry`, `retry-after-ms` and `Retry-After` headers count.
        /// - Returns: The retry, or `nil` when the request has made its retries, the status isn't retried, or the
        ///   response asks for a longer wait than the policy allows.
        func retry(_ number: Int, status: Int, response: HTTPURLResponse?) -> Retry? {
            guard number <= retries,
                retriesResponse(status, response?.value(forHTTPHeaderField: HTTPHeaderName.shouldRetry.rawValue)),
                let wait = wait(number - 1, HTTPClient.retryAfter(of: response))
            else { return nil }
            return Retry(status: status, error: nil, wait: wait, number: number, limit: retries)
        }

        /// The retry of a request whose connection failed, or `nil` when the request fails at once.
        ///
        /// - Parameters:
        ///   - number: The retry's number, from 1.
        ///   - error: The connection's error.
        /// - Returns: The retry, or `nil` when the request has made its retries or the error isn't retried.
        func retry(_ number: Int, after error: URLError) -> Retry? {
            guard number <= retries, Self.connectionErrors.contains(error.code), let wait = wait(number - 1, nil)
            else { return nil }
            return Retry(status: nil, error: error, wait: wait, number: number, limit: retries)
        }
    }

    /// A request that's sent again: what failed, and how long it waits first.
    struct Retry: Sendable {
        /// The failed response's status, or `nil` when the connection failed.
        let status: Int?

        /// The failed connection's error, or `nil` when a response failed.
        let error: URLError?

        /// The wait before the request is sent again.
        let wait: Duration

        /// The retry's number, from 1.
        let number: Int

        /// The most times the request is sent again.
        let limit: Int
    }
}

extension HTTPClient.RetryPolicy {
    /// The errors of a failed connection after which a request is sent again: a connection that couldn't be made, timed
    /// out or was lost, or that brought back a response that isn't HTTP.
    private static let connectionErrors: Set<URLError.Code> = [
        .timedOut, .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost,
        .secureConnectionFailed, .badServerResponse,
    ]

    /// Up to `retries` retries of a failed connection or a response whose status `statuses` retries, with a wait that
    /// doubles from `delay` up to `longestDelay` and is cut by up to a quarter at random.
    ///
    /// A response's `x-should-retry` decides when it's `true` or `false`, whatever the status. A response that asks in
    /// `retry-after-ms` or `Retry-After` for a wait more than zero and at most `longestRetryAfter` waits that long
    /// instead, and one that asks for more fails at once.
    ///
    /// - Parameters:
    ///   - retries: The most times a request is sent again.
    ///   - statuses: Whether a status is retried, when `x-should-retry` doesn't say.
    ///   - delay: The wait before the first retry, before it's cut.
    ///   - longestDelay: The longest wait that doubling reaches.
    ///   - longestRetryAfter: The longest wait a response can ask for and still be retried, after that wait.
    /// - Returns: The policy.
    static func exponentialBackoff(
        retries: Int,
        statuses: @escaping @Sendable (Int) -> Bool,
        delay: Duration,
        longestDelay: Duration,
        longestRetryAfter: Duration
    ) -> Self {
        Self(
            retries: retries,
            retriesResponse: { status, shouldRetry in
                switch shouldRetry {
                case "true": true
                case "false": false
                default: statuses(status)
                }
            },
            wait: { retried, asked in
                if let asked {
                    if asked > longestRetryAfter { return nil }
                    if asked > .zero { return asked }
                }
                let doubled = (0..<retried).reduce(delay) { wait, _ in Swift.min(wait * 2, longestDelay) }
                return Swift.min(doubled, longestDelay) * (1 - 0.25 * Double.random(in: 0..<1))
            })
    }
}

/// The statuses of a failed response that a request retries. A response's `x-should-retry` wins over its status either
/// way.
package enum RetriedStatuses: Sendable {
    /// A 408, 409 or 429, or any status from 500 up: failures that may clear on another try.
    case transient

    /// Any status from 500 to 599: a server that's failing or overloaded.
    case serverErrors

    /// Whether a failed response's status is retried.
    ///
    /// - Parameter status: The response's status.
    /// - Returns: Whether it's retried, when the response's `x-should-retry` doesn't say.
    @Sendable
    package func contains(_ status: Int) -> Bool {
        switch self {
        case .transient: [408, 409, 429].contains(status) || status >= 500
        case .serverErrors: (500..<600).contains(status)
        }
    }
}

extension RequestRetries {
    /// The retry policy these settings make, for a provider that retries a response whose status `statuses` retries.
    ///
    /// - Parameter statuses: Whether a response's status is retried when its `x-should-retry` doesn't say.
    /// - Returns: The policy.
    func policy(statuses: @escaping @Sendable (Int) -> Bool) -> HTTPClient.RetryPolicy {
        let delay = max(initialDelay, .zero)
        return .exponentialBackoff(
            retries: max(limit, 0), statuses: statuses, delay: delay, longestDelay: delay * 16,
            longestRetryAfter: max(longestServerWait, .zero))
    }
}

// MARK: - Waits a server asks for

extension Duration {
    /// The longest wait a header can ask for. A longer one, or one too large to represent, is cut to this.
    private static let longestRetryDelay = 86_400.0

    /// The delay in a `Retry-After` header: a number of seconds, or an HTTP date.
    init?(retryAfter header: String?, now: Date = .now) {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty else { return nil }
        if let seconds = Double(header) {
            self.init(clampedSeconds: seconds)
            return
        }
        let strategy = Date.ParseStrategy(
            format:
                "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .gmt
        )
        guard let date = try? Date(header, strategy: strategy) else { return nil }
        self.init(clampedSeconds: date.timeIntervalSince(now))
    }

    /// The delay in a `retry-after-ms` header, in milliseconds.
    init?(retryAfterMilliseconds header: String?) {
        guard let header, let milliseconds = Double(header.trimmingCharacters(in: .whitespaces)), milliseconds.isFinite else {
            return nil
        }
        self.init(clampedSeconds: milliseconds / 1_000)
    }

    /// The delay until the time in an `X-RateLimit-Reset` header, in milliseconds or seconds since 1970.
    package init?(rateLimitReset header: String?, now: Date = .now) {
        guard let header, let value = Double(header.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
        // Times in milliseconds are past 1e11; in seconds, that's the year 5138.
        let reset = Date(timeIntervalSince1970: value > 1e11 ? value / 1_000 : value)
        self.init(clampedSeconds: reset.timeIntervalSince(now))
    }

    /// A delay of the given seconds, at least zero and at most the longest a header can ask for.
    private init?(clampedSeconds seconds: Double) {
        guard !seconds.isNaN else { return nil }
        self = .seconds(Swift.min(Swift.max(seconds, 0), Self.longestRetryDelay))
    }
}

// MARK: - Redirects

/// Follows a redirect only to the scheme, host and port the request went to, so its credentials never reach another
/// server. A followed redirect keeps the request's credentials.
///
/// A redirect elsewhere isn't followed, and the redirect response itself comes back, as a failed request.
final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    // `@concurrent`, because the compiler crashes building the Objective-C thunk of a `nonisolated(nonsending)`
    // delegate method (Swift 6.4.2).
    @concurrent
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let originalRequest = task.originalRequest, let original = originalRequest.url, let target = request.url,
            Origin(original) == Origin(target)
        else { return nil }
        // URLSession drops `Authorization` from a redirected request, even to the same server.
        var followed = request
        if followed.value(forHTTPHeaderField: HTTPHeaderName.authorization.rawValue) == nil,
            let authorization = originalRequest.value(forHTTPHeaderField: HTTPHeaderName.authorization.rawValue)
        {
            followed.setValue(authorization, forHTTPHeaderField: HTTPHeaderName.authorization.rawValue)
        }
        return followed
    }
}

extension SameHostRedirects {
    /// A URL's scheme, host and port, compared without case and with the scheme's default port filled in.
    private struct Origin: Equatable {
        let scheme: String?
        let host: String?
        let port: Int?

        init(_ url: URL) {
            scheme = url.scheme?.lowercased()
            host = url.host()?.lowercased()
            port = url.port ?? ["https": 443, "http": 80][scheme ?? ""]
        }
    }
}

// MARK: - User agent

/// The `User-Agent` that names the package on every request, such as
/// `swift-language-models (com.example.Planner/2.3; Swift/6.4; iOS/27.0.1)`.
///
/// The package's name comes first, so a provider credits the traffic to it, whichever app sends it. The app's bundle
/// id and version follow, read from the main bundle, then the Swift and operating system versions. Outside an app
/// bundle, as in a command-line tool or a test, the app is left out. It's what the app reports about itself, for a
/// provider's statistics, not proof of anything.
enum UserAgent {
    /// The `User-Agent` of this process.
    static let current = value(app: app(of: .main), swiftVersion: swiftVersion, system: system)

    /// A `User-Agent`: the package, then a comment of the app, the Swift version and the operating system.
    ///
    /// - Parameters:
    ///   - app: The app's bundle id and version, such as `com.example.Planner/2.3`, or `nil` to leave the app out.
    ///   - swiftVersion: The version of the Swift compiler that built the package, such as `6.4`.
    ///   - system: The operating system and its version, such as `iOS/27.0.1`.
    /// - Returns: The header's value.
    static func value(app: String?, swiftVersion: String, system: String) -> String {
        let comment = [app, "Swift/\(swiftVersion)", system].compactMap(\.self).joined(separator: "; ")
        return "swift-language-models (\(comment))"
    }

    /// The bundle id and version of an app or app extension's bundle, such as `com.example.Planner/2.3`.
    ///
    /// - Parameter bundle: The bundle, usually the main one.
    /// - Returns: The bundle id, and its version when the bundle has one, or `nil` for a bundle that isn't an app's
    ///   or an app extension's.
    static func app(of bundle: Bundle) -> String? {
        guard ["app", "appex"].contains(bundle.bundleURL.pathExtension), let id = bundle.bundleIdentifier else { return nil }
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        return version.map { "\(id)/\($0)" } ?? id
    }

    /// The version of the Swift compiler that built the package, as precisely as the package knows: the newest version
    /// it names, or the oldest it builds with.
    private static var swiftVersion: String {
        #if compiler(>=6.6)
        "6.6"
        #elseif compiler(>=6.5)
        "6.5"
        #else
        "6.4"
        #endif
    }

    /// The operating system's name and version, such as `iOS/27.0.1`.
    private static var system: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #if targetEnvironment(macCatalyst)
        return "macCatalyst/\(number)"
        #elseif os(iOS)
        return "iOS/\(number)"
        #elseif os(macOS)
        return "macOS/\(number)"
        #elseif os(visionOS)
        return "visionOS/\(number)"
        #elseif os(watchOS)
        return "watchOS/\(number)"
        #else
        return "unknown/\(number)"
        #endif
    }
}

// MARK: - Headers and media types

/// The headers of a provider's response, which a provider reads by name.
struct ResponseHeaders: Sendable {
    private let response: HTTPURLResponse?

    init(_ response: HTTPURLResponse?) {
        self.response = response
    }

    /// The value of a header by its name, as a provider asks for it, or `nil` when the response has none.
    func value(named name: String) -> String? {
        response?.value(forHTTPHeaderField: name)
    }
}

/// The name of an HTTP header, such as `Authorization`.
///
/// Header names are compared as written when a provider's headers merge over the authentication's, so each is spelled
/// the same way everywhere.
struct HTTPHeaderName: ProviderVocabulary {
    /// The media types a response may have.
    fileprivate static let accept: Self = "Accept"

    /// The credentials of a request, such as `Bearer …`.
    static let authorization: Self = "Authorization"

    /// The media type of a request's body.
    fileprivate static let contentType: Self = "Content-Type"

    /// How long a response asks to wait before trying again.
    static let retryAfter: Self = "Retry-After"

    /// How long a response asks to wait before trying again, in milliseconds, which takes precedence over
    /// `Retry-After`.
    static let retryAfterMilliseconds: Self = "retry-after-ms"

    /// Whether a response says the request may be sent again: `true` or `false`.
    static let shouldRetry: Self = "x-should-retry"

    /// The client that sends a request.
    fileprivate static let userAgent: Self = "User-Agent"

    let rawValue: String
}

/// The HTTP methods that providers' requests use.
enum HTTPMethod {
    fileprivate static let get = "GET"
    static let post = "POST"
}

/// The media types that providers' requests and attachments use.
enum MediaType {
    static let eventStream = "text/event-stream"
    static let jpeg = "image/jpeg"
    fileprivate static let json = "application/json"
    static let pdf = "application/pdf"
}
