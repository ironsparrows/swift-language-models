import Foundation
package import FoundationModels
package import LanguageModelsCore

/// A format's request for one Foundation Models request: the body it sends, and what it changed from what the app
/// asked for.
package protocol FormatRequest {
    /// The request's body.
    var body: JSONValue { get }

    /// The same body with its response schema in portable form, to send instead when a host rejects a constraint of
    /// the full schema, or `nil` when the request has no schema.
    var portableSchemaBody: JSONValue? { get }

    /// What the request leaves out or changes from what the app asked for, in the log's order.
    var adjustments: [RequestAdjustment] { get }
}

/// The executor of an API format, which sends a dialect's requests and streams each answer into Foundation Models.
///
/// Each format says how it builds its request, which headers its dialect adds, what a rejected request becomes and how
/// its stream reads; ``respond(to:streamingInto:)`` does the rest the same way for every format: it logs what it sends
/// and changes, opens the stream with the portable-schema retry, reads the stream, ends the answer and logs how it
/// ended.
package protocol FormatExecutor {
    associatedtype Dialect: ProviderDialect
    associatedtype Request: FormatRequest
    associatedtype Answer: StreamedAnswer

    /// The provider's dialect of the request.
    var dialect: Dialect { get }

    /// The path of the format's call under the provider's base URL, such as `responses`.
    static var path: String { get }

    /// The body's members that aren't options, such as the model and the transcript, which the log leaves out.
    static var nonOptions: Set<String> { get }

    /// The format's request for Foundation Models' request.
    ///
    /// - Throws: `LanguageModelError` when the format or the dialect can't take the request, and the dialect's errors.
    func request(for request: LanguageModelExecutorGenerationRequest) throws -> Request

    /// The dialect's headers for the request, which take precedence over the authentication's.
    func headers(for request: LanguageModelExecutorGenerationRequest) -> [HTTPHeaderName: String]

    /// The error a response whose status isn't a success becomes, after the retries.
    func error(rejecting failure: ProviderHTTP.Failure, of request: Request) -> any Error

    /// The stream of the request's answer, before its first event.
    func answer(
        to request: Request,
        of generationRequest: LanguageModelExecutorGenerationRequest,
        streamingInto channel: LanguageModelExecutorGenerationChannel,
        headers: ResponseHeaders
    ) -> Answer
}

extension FormatExecutor {
    /// Sends one request and streams its answer.
    ///
    /// - Returns: The answer's response text, or empty text when the answer ends in tool calls.
    /// - Throws: What the format and the dialect throw, a failed connection's error as `URLError` maps it, what the
    ///   authentication throws, and `CancellationError` when the task is cancelled.
    package func respond(
        to request: LanguageModelExecutorGenerationRequest,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws -> DetailedLanguageModelAnswer {
        try await OperationLog(request: request.id, logger: Dialect.logger).run { log in
            let formatRequest = try self.request(for: request)
            let model = dialect.modelID.rawValue
            log.sending(formatRequest.body, to: model, leavingOut: Self.nonOptions)
            for adjustment in formatRequest.adjustments {
                log.report(adjustment, model: model, provider: Dialect.name)
            }
            let opened: (URLSession.AsyncBytes, ResponseHeaders)
            do {
                opened = try await dialect.connection.openEventStream(
                    body: formatRequest.body, portableSchemaBody: formatRequest.portableSchemaBody, headers: headers(for: request),
                    url: { try dialect.baseURL.appending(path: Self.path) }, log: log)
            } catch let rejected as ProviderHTTP.Failure {
                throw error(rejecting: rejected, of: formatRequest)
            }
            var answer = self.answer(to: formatRequest, of: request, streamingInto: channel, headers: opened.1)
            let isComplete = try await log.read(opened.0, into: &answer)
            try await answer.finish(isComplete: isComplete)
            log.finished(answer.report, host: answer.host)
            return DetailedLanguageModelAnswer(responseText: answer.responseText)
        }
    }
}
