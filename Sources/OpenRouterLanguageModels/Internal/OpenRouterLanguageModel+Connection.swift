import LanguageModels

extension OpenRouterLanguageModel {
    /// How the model's requests reach OpenRouter: its session and authentication, with the timeout and retries of its
    /// configuration. Chat requests and info calls both go through it.
    func connection(_ configuration: OpenRouterConfiguration) -> Connection {
        Connection(
            session: session, authentication: auth.requestAuthentication, idleTimeout: configuration.idleTimeout,
            retries: configuration.retries, retrying: API.retriesStatus)
    }
}
