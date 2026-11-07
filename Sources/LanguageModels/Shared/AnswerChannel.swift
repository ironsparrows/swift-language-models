import Foundation
package import FoundationModels
package import LanguageModelsCore

/// Where one answer's output goes: the Foundation Models channel events of its response, reasoning, tool-call and data
/// entries, whatever format the provider streams it in.
///
/// Each kind of output keeps one entry id for the whole answer, because the framework only merges events into the entry
/// they name. Reasoning text that arrives after the answer's text starts isn't shown. For a format that reads tagged
/// reasoning, a block in `<think>` or `<thinking>` tags that opens the answer's text is reasoning too, in arrival order
/// with the provider's reasoning; the reasoning entry keeps the block as the model wrote it, so it goes back where the
/// model put it. Tool-call fragments
/// are routed by index into one tool-calls entry, so parallel calls form one round. Each piece of data the model
/// generates becomes a data entry of its own. The answer ends with its metadata and usage on the entry that finishes
/// it, and with the pages it cites on its response entry.
package struct AnswerChannel {
    private let channel: LanguageModelExecutorGenerationChannel

    /// The origin the answer's reasoning entry carries, so that only the provider's own reasoning goes back.
    private let origin: ReasoningOrigin

    private let responseEntryID = UUID().uuidString
    private let reasoningEntryID = UUID().uuidString
    private let toolCallsEntryID = UUID().uuidString

    private var sentText = ""
    private var hasText = false
    private var hasReasoning = false
    /// The reasoning block that opens the answer's text, or `nil` for a format that doesn't read one.
    private var taggedReasoning: TaggedReasoning?
    private var toolCalls = ToolCallAssembler()
    private var citations: [Citation] = []

    /// - Parameters:
    ///   - channel: Where the answer's events go.
    ///   - origin: The origin the answer's reasoning entry carries.
    ///   - readsTaggedReasoning: Whether a block in reasoning tags that opens the answer's text is reasoning, as for a
    ///     format whose models may write their reasoning there. A format with reasoning of its own sends such text as
    ///     the answer's.
    package init(channel: LanguageModelExecutorGenerationChannel, origin: ReasoningOrigin, readsTaggedReasoning: Bool) {
        self.channel = channel
        self.origin = origin
        taggedReasoning = readsTaggedReasoning ? TaggedReasoning() : nil
    }

    /// The text sent to the response entry, or empty when the answer ends in tool calls, since the round that answers
    /// them comes after.
    package var responseText: String {
        toolCalls.isEmpty ? sentText : ""
    }

    /// Whether any of the answer's output has arrived: text, reasoning or a tool call.
    package var hasOutput: Bool {
        hasText || hasReasoning || !toolCalls.isEmpty
    }

    /// Whether a fragment of a tool call has arrived.
    package var hasToolCalls: Bool {
        !toolCalls.isEmpty
    }

    /// Sends the next part of the answer's text, with a reasoning block in tags that opens it sent as reasoning when
    /// the format reads one.
    ///
    /// - Parameters:
    ///   - delta: The next part of the text.
    ///   - model: The model that answered, once known, which the reasoning entry names.
    package mutating func appendText(_ delta: String, model: String?) async {
        await send(taggedReasoning?.split(delta) ?? TaggedReasoning.Split(text: delta), model: model)
    }

    /// Sends reasoning text, which shows only until the answer's text starts. Empty text starts the reasoning entry
    /// without text.
    ///
    /// - Parameters:
    ///   - text: The reasoning text.
    ///   - model: The model that answered, once known, which the reasoning entry names.
    package mutating func appendReasoning(_ text: String, model: String?) async {
        if !hasReasoning {
            hasReasoning = true
            await channel.send(.reasoning(entryID: reasoningEntryID, action: .updateMetadata(reasoningMetadata(model: model))))
        }
        guard !text.isEmpty, !hasText else { return }
        await channel.send(.reasoning(entryID: reasoningEntryID, action: .appendText(text, tokenCount: 1)))
    }

    /// Adds one tool-call fragment to its call, as ``ToolCallAssembler/add(index:id:name:arguments:)`` routes it, and
    /// sends the arguments it starts or adds.
    package mutating func addToolCall(index: Int?, id: String?, name: String?, arguments: String?) async {
        if let arguments = toolCalls.add(index: index, id: id, name: name, arguments: arguments) {
            await channel.send(arguments.event(in: toolCallsEntryID))
        }
    }

    /// Adds a page the answer cites, once.
    package mutating func cite(_ citation: Citation) {
        if !citations.contains(citation) { citations.append(citation) }
    }

    /// Sends data the model generated as a data entry of its own.
    ///
    /// Before the OS version that has data entries, and in a build with an SDK before Xcode 27.2's, nothing is sent.
    package func sendData(_ data: GeneratedData) async {
        #if canImport(FoundationModels, _version: 2.1.14)
        guard #available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *) else { return }
        await channel.send(.data(entryID: UUID().uuidString, action: .update(contentType: data.contentType, content: data.content)))
        #endif
    }

    /// Sends the text held back while it could still be the start of a reasoning block, once the stream is over.
    ///
    /// - Parameter model: The model that answered, which the reasoning entry names.
    private mutating func finishText(model: String?) async {
        guard let split = taggedReasoning?.finish() else { return }
        await send(split, model: model)
    }

    /// Ends the tool calls: sends empty JSON as the arguments of each call that got none.
    ///
    /// - Throws: The problem when a call never got its name or its arguments aren't a whole JSON object, before any
    ///   tool runs with them.
    private func finishToolCalls() async throws(StreamProblem) {
        let calls: [ToolCallAssembler.Arguments]
        do {
            calls = try toolCalls.finish()
        } catch {
            switch error {
            case .missingName: throw .toolCallWithoutName
            case .incompleteArguments(let toolName): throw .incompleteToolArguments(toolName: toolName)
            }
        }
        for arguments in calls {
            await channel.send(arguments.event(in: toolCallsEntryID))
        }
    }

    /// Ends an answer whose stream ended: sends the text held back, then empty JSON as the arguments of each call that
    /// got none, then the reasoning signature and the answer's facts and usage, unless the answer fails anyway.
    ///
    /// The answer fails, in this order, when the model declined, a content filter stopped it, it reached its token
    /// limit inside a tool call or a guided answer, the host says it failed, or a call never got its name or has
    /// arguments that aren't a whole JSON object. An answer cut off at its token limit otherwise ends like any other,
    /// with `length` as its finish reason, since Foundation Models has no error for it.
    ///
    /// - Parameters:
    ///   - report: What the format's own members reported about the answer.
    ///   - facts: What the provider adds to them.
    ///   - refusal: The refusal text the model sent, empty for none.
    ///   - requiresCompleteAnswer: Whether the answer must be whole, as a guided answer must.
    ///   - failedAnswer: The format's error for an answer the host says failed, or `nil` when it doesn't say so.
    /// - Returns: Why the answer fails, or `nil` when it ended.
    package mutating func finish(
        report: AnswerReport,
        facts: AnswerFacts,
        refusal: String,
        requiresCompleteAnswer: Bool,
        failedAnswer: (any Error)? = nil
    ) async -> AnswerFailure? {
        await finishText(model: report.model)
        let ending = AnswerEnding(
            refusal: refusal, finishReason: report.finishReason, hasToolCalls: hasToolCalls,
            requiresCompleteAnswer: requiresCompleteAnswer)
        if ending == .tokenLimitInToolCall { return .unusable(.tokenLimitInToolCall) }
        if let error = ending?.error(responseText: responseText, host: facts.host) ?? failedAnswer { return .failed(error) }
        do {
            try await finishToolCalls()
        } catch {
            return .unusable(error)
        }
        await end(report: report, facts: facts)
        return nil
    }

    /// Ends the answer: the reasoning entry with the provider's signature, then the answer's facts and usage on the
    /// entry that ends it.
    ///
    /// - Parameters:
    ///   - report: What the format's own members reported about the answer.
    ///   - facts: What the provider adds to them.
    private mutating func end(report: AnswerReport, facts: AnswerFacts) async {
        await endReasoning(signature: facts.reasoningSignature, model: report.model)
        await sendFacts(report: report, facts: facts)
    }

    /// Ends the reasoning entry, when the provider has a signature for it or the model wrote a block in its answer's
    /// text: with the signature, and with the metadata that sending it back needs.
    private mutating func endReasoning(signature: Data?, model: String?) async {
        guard signature != nil || taggedReasoning?.block != nil else { return }
        await appendReasoning("", model: model)
        if let signature {
            await channel.send(.reasoning(entryID: reasoningEntryID, action: .updateSignature(signature, tokenCount: 0)))
        }
        // The model may arrive after the reasoning started, and the block is known only now; replay needs both.
        await channel.send(.reasoning(entryID: reasoningEntryID, action: .updateMetadata(reasoningMetadata(model: model))))
    }

    /// Sends the answer's facts and usage on the entry that ends it: the response entry, or the tool-calls entry when
    /// tool calls end the answer.
    private func sendFacts(report: AnswerReport, facts: AnswerFacts) async {
        var metadata = report.metadata
        metadata.merge(facts.metadata) { $1 }
        let usage = report.usage
        let usageMetadata = usage.map { $0.metadata.merging(facts.usageMetadata) { $1 } }
        // Foundation Models keeps only the last request's usage on a response, so each request's usage facts also go
        // on the entry that ends it, where a response whose tool calls ran reads every request's cost.
        metadata.merge(usageMetadata ?? [:]) { $1 }
        // Citations point into the answer's text, so they go on the response entry even when tool calls end the answer.
        let citations = self.citations.isEmpty ? nil : self.citations.map(\.metadataValue)
        if toolCalls.isEmpty {
            if !hasText { await channel.send(.response(entryID: responseEntryID, action: .appendText("", tokenCount: 0))) }
            metadata[LanguageModelMetadataKey.citations] = citations
            await channel.send(.response(entryID: responseEntryID, action: .updateMetadata(metadata)))
            if let usage, let usageMetadata {
                await channel.send(
                    .response(
                        entryID: responseEntryID, action: .updateUsage(input: usage.input, output: usage.output, metadata: usageMetadata))
                )
            }
        } else {
            if hasText, let citations {
                await channel.send(
                    .response(entryID: responseEntryID, action: .updateMetadata([LanguageModelMetadataKey.citations: citations])))
            }
            // Foundation Models gives the tool-calls entry no readable metadata, so the round's facts go on its first call.
            if let first = toolCalls.firstCall {
                await channel.send(
                    .toolCalls(
                        entryID: toolCallsEntryID,
                        action: .toolCall(id: first.id, name: first.toolName, action: .updateMetadata(metadata))))
            }
            if let usage, let usageMetadata {
                await channel.send(
                    .toolCalls(
                        entryID: toolCallsEntryID, action: .updateUsage(input: usage.input, output: usage.output, metadata: usageMetadata))
                )
            }
        }
    }

    /// The reasoning entry's metadata: the origin, the model that wrote it once known, and the block that opened the
    /// answer's text once the answer ended.
    private func reasoningMetadata(model: String?) -> [String: any ConvertibleToGeneratedContent] {
        origin.metadata(model: model, taggedBlock: taggedReasoning?.block)
    }

    /// Sends a split of the answer's text: its reasoning, then its answer text.
    private mutating func send(_ split: TaggedReasoning.Split, model: String?) async {
        if !split.reasoning.isEmpty { await appendReasoning(split.reasoning, model: model) }
        guard !split.text.isEmpty else { return }
        hasText = true
        sentText += split.text
        await channel.send(.response(entryID: responseEntryID, action: .appendText(split.text, tokenCount: 1)))
    }
}
