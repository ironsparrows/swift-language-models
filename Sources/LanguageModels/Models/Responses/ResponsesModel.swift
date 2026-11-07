package import Foundation
package import FoundationModels
package import LanguageModelsCore

// MARK: - Model

/// OpenAI's Responses format: the model that speaks it, and what a provider may add.
package enum Responses {}

extension Responses {
    /// A model that speaks the Responses format with any provider that takes it.
    ///
    /// The model owns the whole exchange: it builds the body from Foundation Models' request, authenticates and sends it,
    /// retries a brief failure as its connection allows and once with the portable schema when a host rejects a
    /// constraint, streams the answer into Foundation Models' channel, sends each answer's `reasoning` items back on
    /// later turns in the order they came, maps a failed connection and logs. Its stored properties say what's true for
    /// every request: a provider states the ones the initializer takes, and the rest default to the plain format. Its
    /// ``exchange`` is the provider's part in each one.
    package struct Model<Exchange: Responses.Exchange>: LanguageModel {
        // MARK: Where requests go

        /// The model's id, sent as `model`.
        var name: String

        /// The provider's base URL, which `responses` goes under.
        var url: URL

        /// How requests reach the provider: the URL session, authentication, idle timeout and retries.
        var connection: Connection

        /// The provider's name, as the log's category and error messages name it.
        var providerName: String

        /// What the model can do, which Foundation Models checks before a request.
        package var capabilities: LanguageModelCapabilities

        /// The models a request may reach, in the order the provider tries them, which each request looks through for one
        /// its provider stopped listing.
        package let reachableModels: [any ModelDetails]

        // MARK: How the provider differs from the plain format

        /// The members the model doesn't take, the format's or the provider's, which a request leaves out and logs.
        package var unsupportedMembers: Set<Member> = []

        /// The role of the message the instructions go in.
        package var instructionsRole = InstructionsRole.developer

        /// How the request's image attachments are encoded.
        let images: ImageEncoding

        /// The origin the reasoning entries of the provider's answers carry, so that only its own reasoning goes back.
        /// Saved transcripts keep it, so a provider never changes it.
        let reasoningOrigin: String

        /// The metadata key under which an answer's response entry keeps the `phase` of each of its messages, such as
        /// `commentary` or `final_answer`, with the length of its text, so each message goes back with its phase on
        /// later turns. Saved transcripts keep it, so a provider never changes it.
        let phasesKey: String

        // MARK: The provider's part in each request

        /// What the provider does in each exchange. Each request works on a copy of it.
        var exchange: Exchange

        /// Creates a model.
        ///
        /// - Parameters:
        ///   - name: The model's id, sent as `model`.
        ///   - url: The provider's base URL.
        ///   - connection: How requests reach the provider.
        ///   - providerName: The provider's name, as the log's category and error messages name it.
        ///   - images: How the request's image attachments are encoded.
        ///   - reasoningOrigin: The origin the reasoning entries of the provider's answers carry.
        ///   - phasesKey: The metadata key of an answer's message phases.
        ///   - capabilities: What the model can do.
        ///   - models: The models a request may reach, in the order the provider tries them, so each request reports
        ///     the ones their provider stopped listing.
        ///   - exchange: What the provider does in each exchange.
        package init(
            name: String, url: URL, connection: Connection, providerName: String, images: ImageEncoding, reasoningOrigin: String,
            phasesKey: String, capabilities: LanguageModelCapabilities, reaching models: [any ModelDetails], exchange: Exchange
        ) {
            self.name = name
            self.url = url
            self.connection = connection
            self.providerName = providerName
            self.images = images
            self.reasoningOrigin = reasoningOrigin
            self.phasesKey = phasesKey
            self.capabilities = capabilities
            reachableModels = models
            self.exchange = exchange
        }
    }

    /// The role of the input message the instructions go in, as ``Model/instructionsRole`` picks it.
    package struct InstructionsRole: ProviderVocabulary {
        /// Instructions from the app's developer, which take priority over the person's messages.
        package static let developer: Self = "developer"

        /// System instructions, for models that don't take the `developer` role.
        package static let system: Self = "system"

        package let rawValue: String

        package init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

// MARK: - Answering

extension Responses.Model {
    /// Sends one request and streams its answer, with the checks every model runs around the exchange: the removed-model
    /// report before it, and the schema's guides after it, since a host may ignore a guide.
    ///
    /// - Parameters:
    ///   - generation: The transcript, tools, schema and options to send.
    ///   - channel: Where the answer's events go.
    /// - Throws: What ``run(_:streamingInto:)`` throws, and `GeneratedContent.ParsingError` when a value of the answer
    ///   breaks a guide of the request's schema or an object or array answer isn't complete JSON.
    package func respond(
        to generation: LanguageModelExecutorGenerationRequest,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        [ModelRemovals.Report](reaching: reachableModels).report(for: generation)
        let text = try await run(generation, streamingInto: channel)
        try GuideViolations.check(text, of: generation)
    }

    /// Runs one exchange: reads the request, sends it and streams its answer.
    ///
    /// A request is retried as the connection says, only before any data arrives, such as after a timeout, a server
    /// error or a briefly unavailable gateway or host, never when its `x-should-retry` is `false`, and once with the
    /// portable schema when the host rejects a constraint of the full one. The answer streams into the channel, and its
    /// `reasoning` items go back on later turns in the order they came. Every failure becomes what the exchange's
    /// ``Responses/Exchange/error(for:)`` makes of it.
    ///
    /// - Parameters:
    ///   - generation: The transcript, tools, schema and options to send.
    ///   - channel: Where the answer's events go.
    /// - Returns: The answer's response text, or empty text when the answer ends in tool calls.
    /// - Throws: `LanguageModelError` for failures Foundation Models has a case for, what the exchange makes of the
    ///   rest, a failed connection's error as `URLError` maps it, what the authentication throws, and
    ///   `CancellationError` when the task is cancelled.
    private func run(
        _ generation: LanguageModelExecutorGenerationRequest,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws -> String {
        var exchange = exchange
        var log = RequestLog(request: generation.id, logger: PackageLogger(category: providerName))
        do {
            // 1. Read the transcript, tools, schema and options. The exchange checks attachments and picks reasoning.
            var request = try Responses.Request(generation, model: self, exchange: exchange)
            // 2. The provider adds its members and choices.
            try exchange.prepare(&request)
            // 3. One ordered body, and what it leaves out or changes.
            let body = try request.body()
            log.sending(body.json, to: name, leavingOut: Responses.Member.nonOptions)
            for adjustment in body.adjustments { log.report(adjustment, model: name, provider: providerName) }
            // 4. Send. Retries before any data, and once more with the portable schema.
            let (bytes, headers) = try await open(body, imageEntries: request.imageEntries, exchange: exchange, log: log)
            // 5. Events into the answer's output. The stream owns the exchange from here.
            var stream = Responses.Stream(
                channel: channel, model: self, exchange: exchange, headers: headers, imageEntries: request.imageEntries,
                requiresCompleteAnswer: generation.schema != nil)
            for try await event in ServerSentEvent.Events(bytes) {
                try Task.checkCancellation()
                if try await stream.receive(event) { break }
                if stream.hasOutput { log.receivedToken() }
            }
            try Task.checkCancellation()
            // 6. End the answer: tool arguments, signature, facts and usage.
            try await stream.finish()
            log.finished(stream.report, host: stream.host)
            return stream.responseText
        } catch {
            throw log.recordFailure(error)
        }
    }

    /// Sends a request's body, and turns a rejected response into what the exchange makes of it.
    private func open(
        _ body: RequestBody,
        imageEntries: [Transcript.Entry],
        exchange: Exchange,
        log: RequestLog
    ) async throws -> (URLSession.AsyncBytes, ResponseHeaders) {
        do {
            return try await connection.openEventStream(body, headers: [:], url: url.appending(path: "responses"), log: log)
        } catch let rejected as HTTPClient.Failure {
            throw exchange.error(for: RequestFailure(rejected: rejected, imageEntries: imageEntries))
        }
    }
}

// MARK: - Executor

extension Responses.Model {
    /// Foundation Models' way in: it creates the executor and calls it for each answer. It keeps no state between
    /// answers.
    package struct Executor: LanguageModelExecutor {
        /// Holds nothing: the model carries what a request needs.
        package struct Configuration: Hashable, Sendable {}

        package init(configuration: Configuration) {}

        package func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: Responses.Model<Exchange>,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            try await model.respond(to: request, streamingInto: channel)
        }
    }

    package var executorConfiguration: Executor.Configuration {
        Executor.Configuration()
    }
}

// MARK: - Exchange

extension Responses {
    /// A provider's part in one exchange: one request and its answer.
    ///
    /// The model holds one exchange value, set up with the provider's settings. Each request copies it and works on the
    /// copy. The methods are in the order a request calls them. Every one has a default that adds nothing, except
    /// ``error(for:)``, which says what a failure becomes. Implement the methods that have a default in the type that
    /// declares the conformance: only there does a misspelled one draw a warning instead of silently keeping the default.
    package protocol Exchange: Sendable {
        /// The `error` object of the provider's failed responses, `{"error": {…}}`. The default is the one OpenAI's formats
        /// send.
        associatedtype ErrorBody: Decodable & Sendable = APIErrorBody

        // MARK: While the request is read

        /// Checks that the model takes an attachment, before the format reads it. The default takes every one.
        ///
        /// - Throws: `LanguageModelError` for an attachment the model doesn't take.
        func checkAttachment(_ kind: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError)

        /// Whether one of the provider's own reasoning entries goes back in a later request, as the answer's `reasoning`
        /// items. Reasoning another provider wrote never does. The default sends back every one.
        func replays(_ reasoning: Transcript.Reasoning) -> Bool

        // MARK: Before it is sent

        /// Adds the provider's members and choices to the request. The default adds nothing.
        ///
        /// - Throws: `LanguageModelError` when the provider can't send the request.
        mutating func prepare(_ request: inout Request) throws

        // MARK: When it ends, or fails

        /// What the provider adds to the answer once it's over. Its reasoning signature is ignored, since the format's
        /// holds the answer's `reasoning` items. The default adds nothing.
        ///
        /// - Parameter header: Reads a header of the response whose stream carries the answer.
        /// - Returns: What the provider adds.
        func additions(header: (String) -> String?) -> AnswerAdditions

        /// What a failure becomes: Foundation Models' error when it has a case for it, otherwise the provider's own. What each
        /// status stands for reads best as a `switch` over ``HTTPStatus`` with no `default`, so a status named later has to
        /// be decided.
        ///
        /// - Parameter failure: The failure.
        /// - Returns: The error a session throws.
        func error(for failure: RequestFailure<ErrorBody>) -> any Error
    }
}

// MARK: - Plain exchange

extension Responses {
    /// An exchange that adds nothing, for a provider that takes the format as it is. Its errors are the failures
    /// themselves.
    package struct PlainExchange: Exchange {
        package func error(for failure: RequestFailure<APIErrorBody>) -> any Error {
            failure
        }
    }
}

extension Responses.Model where Exchange == Responses.PlainExchange {
    /// Creates a model that speaks the plain format: to a server that needs no credentials, with no idle timeout of its
    /// own, retrying transient failures, with every capability Foundation Models names. The URL's host stands
    /// for the provider's name, which the log, error messages, and the tags on its answers' reasoning and messages use.
    ///
    /// - Parameters:
    ///   - name: The model's id, sent as `model`.
    ///   - url: The server's base URL.
    package init(name: String, url: URL) {
        let providerName = url.host() ?? name
        self.init(
            name: name, url: url, connection: .unauthenticated, providerName: providerName, images: .standard,
            reasoningOrigin: "\(providerName.lowercased())-responses",
            phasesKey: "\(providerName.prefix(1).lowercased())\(providerName.dropFirst()).phases",
            capabilities: LanguageModelCapabilities([.toolCalling, .guidedGeneration, .reasoning, .vision]), reaching: [],
            exchange: Responses.PlainExchange())
    }
}

// MARK: - Defaults

extension Responses.Exchange {
    package func checkAttachment(_ kind: AttachmentKind, in entry: Transcript.Entry) throws(LanguageModelError) {}

    package func replays(_ reasoning: Transcript.Reasoning) -> Bool { true }

    package mutating func prepare(_ request: inout Responses.Request) throws {}

    package func additions(header: (String) -> String?) -> AnswerAdditions { AnswerAdditions() }
}
