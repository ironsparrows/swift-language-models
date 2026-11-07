import LanguageModels

extension OpenRouterError: LoggableError {
    package var logFields: (kind: String, status: Int?, code: String?, host: String?) {
        ("OpenRouterError", status, code.rawValue, providerName?.rawValue)
    }
}
