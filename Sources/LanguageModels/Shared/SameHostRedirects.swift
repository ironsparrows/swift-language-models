package import Foundation

/// Follows a redirect only to the scheme, host and port the request went to, so its credentials never reach another
/// server. A followed redirect keeps the request's credentials.
///
/// A redirect elsewhere isn't followed, and the redirect response itself comes back, as a failed request.
package final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    // `@concurrent`, because the compiler crashes building the Objective-C thunk of a `nonisolated(nonsending)`
    // delegate method (Swift 6.4.2).
    @concurrent
    package func urlSession(
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
