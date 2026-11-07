package import Foundation

/// How a provider's requests reach it: the URL session that sends them, how they authenticate, how long they wait
/// for data and when a request that fails is sent again.
///
/// A provider builds one from its model and its request executor's configuration, or for a call that has no model, such
/// as a catalog entry's info call. The format's executor and the provider's info calls send requests through it.
package struct ProviderConnection: Sendable {
    /// The URL session that sends the requests.
    package let session: URLSession

    /// The headers that authenticate a request, read for every request.
    package let authentication: RequestAuthentication

    /// How long to wait for the next data, or `nil` for the session's own timeout.
    package let idleTimeout: Duration?

    /// When a request that fails is sent again, and how long it waits first.
    package let retryPolicy: ProviderHTTP.RetryPolicy

    /// Creates a connection whose requests retry as a policy says.
    package init(
        session: URLSession, authentication: RequestAuthentication, idleTimeout: Duration?, retryPolicy: ProviderHTTP.RetryPolicy
    ) {
        self.session = session
        self.authentication = authentication
        self.idleTimeout = idleTimeout
        self.retryPolicy = retryPolicy
    }

    /// The client that sends the connection's requests, retrying them as the retry policy says.
    package var http: ProviderHTTP {
        ProviderHTTP(session: session, retryPolicy: retryPolicy)
    }
}
