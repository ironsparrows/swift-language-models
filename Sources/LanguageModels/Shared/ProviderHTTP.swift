package import Foundation
import LanguageModelsCore

/// Sends a provider's HTTP requests: with the package's `User-Agent`, following redirects only to the same host, and
/// sending a request that fails again as the provider's ``RetryPolicy`` says.
///
/// A request is sent again only before any of its response is read: after a failed connection or a response that the
/// policy retries. A response that asks for a longer wait than the policy allows fails the request at once instead,
/// with the wait on its error, so the app can retry later, and so does one that the policy doesn't retry, such as one
/// whose `x-should-retry` is `false`.
package struct ProviderHTTP: Sendable {
    /// The decoder of every response body and streamed chunk, which requests share, since `JSONDecoder` is
    /// `Sendable`.
    package static let decoder = JSONDecoder()

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
    package init(session: URLSession, retryPolicy: RetryPolicy) {
        self.session = session
        self.retryPolicy = retryPolicy
    }

    /// A response whose status isn't a success, with the start of its body and the delay it asks to wait.
    package struct Failure: Error {
        /// The HTTP status, or 0 for a response that isn't HTTP.
        package let status: Int
        package let body: Data
        package let response: HTTPURLResponse?

        /// The wait the response's `retry-after-ms` or `Retry-After` header asks for.
        package var retryAfter: Duration? {
            ProviderHTTP.retryAfter(of: response)
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
    package static func request(
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
    package func stream(for request: URLRequest, onRetry: (Retry) -> Void = { _ in }) async throws -> (
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
    package func data(for request: URLRequest, onRetry: (Retry) -> Void = { _ in }) async throws -> (Data, HTTPURLResponse?) {
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
    static func retryAfter(of response: HTTPURLResponse?) -> Duration? {
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
