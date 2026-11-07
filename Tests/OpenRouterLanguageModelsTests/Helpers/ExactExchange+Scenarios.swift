import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing
import UniformTypeIdentifiers

@testable import OpenRouterLanguageModels

extension ExactExchange {
    /// Runs a session against a stub and reads what it sent and got back, with OpenRouter's headers: the `X-` ones
    /// and `HTTP-Referer`.
    ///
    /// - Parameters:
    ///   - stub: The stub that stands in for OpenRouter, which records each request.
    ///   - session: The session to run.
    ///   - answer: Sends the prompt and returns the answer's usage, keeping the last snapshot of a streamed answer.
    init(
        _ stub: HTTPStub,
        _ session: LanguageModelSession,
        answer: (LanguageModelSession, inout String?) async throws -> LanguageModelSession.Usage
    ) async {
        await self.init(stub, session, recordingHeaders: /^X-|^HTTP-Referer$/, answer: answer)
    }
}

extension ExactExchange {
    /// Streamed text alone, with instructions, sampling, a token limit, metadata, OpenRouter's settings and a cache mark.
    static func textAlone() async -> ExactExchange {
        let stub = HTTPStub(
            events(
                text("The plan "), adding(["service_tier": "flex"], to: text("starts Monday.")),
                done(prompt: 12, cached: 4, cacheWrite: 2, completion: 5)))
        let options = OpenRouterOptions(
            frequencyPenalty: 0.5, presencePenalty: 0.2, stopSequences: ["END"], logitBias: [13: 2.5, 50_256: -100], verbosity: .low,
            serviceTier: .flex, endUserID: "user-1")
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(
            stub, parameters: chatParameters.union([.frequencyPenalty, .stop, .logitBias, .verbosity, .maxCompletionTokens]),
            cachesOnlyMarkedPrompts: true, options: options)
        let generation = GenerationOptions(
            samplingMode: .random(probabilityThreshold: 0.9, seed: 7), temperature: 0.5, maximumResponseTokens: 100)
        return await ExactExchange(stub, LanguageModelSession(model: model, instructions: "Be brief.")) { session, lastSnapshot in
            try await stream(
                session.streamResponse(to: "Plan the week.", options: generation, metadata: ["team": "coach", "count": 3]),
                into: &lastSnapshot)
        }
    }

    /// A streamed answer that calls a tool twice at once, then the answer to the tools' outputs.
    static func parallelTools() async -> ExactExchange {
        let stub = HTTPStub(
            events(
                text("Looking both up. "), toolCall(0, id: "call_1", name: "lookUpFood", arguments: #"{"food""#),
                toolCall(1, id: "call_2", name: "lookUpFood", arguments: #"{"food":"rice"}"#),
                toolCall(0, arguments: #":"egg"}"#), done("tool_calls")),
            events(text("An egg and rice have 100 kcal each."), done()))
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, options: OpenRouterOptions(parallelToolCalls: .allowed))
        return await ExactExchange(stub, LanguageModelSession(model: model, tools: [FoodTool()])) { session, lastSnapshot in
            try await stream(session.streamResponse(to: "Calories in an egg and rice?"), into: &lastSnapshot)
        }
    }

    /// Guided generation whose host rejects a constraint of the schema, so the request goes again with the portable
    /// schema.
    static func portableSchemaRetry() async -> ExactExchange {
        let rejection = #"""
            {"error":{"code":400,"message":"Provider returned error","metadata":{"provider_name":"Seed","raw":"Keyword 'maximum' is not supported for type 'integer'"}}}
            """#
        let stub = HTTPStub(.json(rejection, status: 400), events(text(#"{"stars":4,"#), text(#""reason":"Tasty."}"#), done()))
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub)
        return await ExactExchange(stub, LanguageModelSession(model: model)) { session, _ in
            try await session.respond(to: "Rate the soup.", generating: SoupRating.self).usage
        }
    }

    #if canImport(FoundationModels, _version: 2.1.14)
    /// An earlier prompt with an image, a labeled PDF and audio, which go back with the next prompt.
    @available(iOS 27.2, macOS 27.2, visionOS 27.2, watchOS 27.2, *)
    static func attachments() async throws -> ExactExchange {
        let stub = HTTPStub(events(text("A menu, a photo and a song."), done()))
        let photo = Transcript.ImageAttachment(try #require(TestImage.halves(width: 8, height: 4)))
        let pdf = Transcript.DataAttachment(contentType: .pdf, content: pdfDocument(showing: "Soup of the day"))
        let audio = Transcript.DataAttachment(contentType: .wav, content: Data("RIFF-wave".utf8))
        let transcript = Transcript(entries: [
            .prompt(
                Transcript.Prompt(segments: [
                    .text(.init(content: "Keep these.")),
                    .attachment(.init(content: .image(photo), label: "Photo")),
                    .attachment(.init(content: .data(pdf), label: "Menu")),
                    .attachment(.init(content: .data(audio))),
                ])),
            .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Kept."))])),
        ])
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(
            stub, inputs: [.text, .image, .file, .audio], options: OpenRouterOptions(pdfEngine: .mistralOCR))
        return await ExactExchange(stub, LanguageModelSession(model: model, transcript: transcript)) { session, _ in
            try await session.respond(to: "What's in these?").usage
        }
    }
    #endif

    /// A reasoning level, and a streamed answer that opens with reasoning in `<think>` tags split across deltas.
    static func taggedReasoning() async -> ExactExchange {
        let stub = HTTPStub(events(text("<thi"), text("nk>Count the days.</th"), text("ink>\n\nSeven"), text(" days."), done()))
        let model: OpenRouterLanguageModel<HighMediumLow> = model(stub, reasoning: .onByDefault, efforts: [.high, .medium, .low])
        return await ExactExchange(stub, LanguageModelSession(model: model)) { session, lastSnapshot in
            try await stream(
                session.streamResponse(to: "How many days in a week?", contextOptions: ContextOptions(reasoningLevel: .moderate)),
                into: &lastSnapshot)
        }
    }

    /// An earlier answer's reasoning details going back, and a streamed answer with new ones.
    static func reasoningDetails() async -> ExactExchange {
        let stub = HTTPStub(
            events(
                reasoning(["type": "reasoning.text", "text": "Two ", "index": 0, "format": "anthropic-claude-v1"]),
                reasoning(["type": "reasoning.text", "text": "weeks.", "index": 0]),
                reasoning(["type": "reasoning.text", "signature": "sig-2", "index": 0]),
                reasoning(["type": "reasoning.encrypted", "data": "blob", "index": 1]),
                text("Fourteen."), done(reasoning: 3)))
        let details: JSONValue = [
            ["type": "reasoning.text", "text": "Count them.", "signature": "sig-1", "format": "anthropic-claude-v1", "index": 0]
        ]
        let earlierReasoning = Transcript.Reasoning(
            metadata: ["reasoningOrigin": "openrouter", "model": "vendor/model"],
            segments: [.text(.init(content: "Count them."))], signature: details.data)
        let transcript = Transcript(entries: [
            .prompt(Transcript.Prompt(segments: [.text(.init(content: "How many days in a week?"))])),
            .reasoning(earlierReasoning),
            .response(Transcript.Response(assetIDs: [], segments: [.text(.init(content: "Seven."))])),
        ])
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub, reasoning: .onByDefault)
        return await ExactExchange(stub, LanguageModelSession(model: model, transcript: transcript)) { session, lastSnapshot in
            try await stream(session.streamResponse(to: "And in a fortnight?"), into: &lastSnapshot)
        }
    }

    /// Fallbacks, a router among them, routing, a server tool, the response cache and the router's report.
    static func fallbacks() async -> ExactExchange {
        let report: JSONValue = ["strategy": "fallback", "attempt": 2, "region": "iad"]
        let stub = HTTPStub(
            events(
                headers: ["X-OpenRouter-Cache-Status": "MISS"],
                adding(["model": "vendor/fallback"], to: text("Hello.")),
                adding(["model": "vendor/fallback", "openrouter_metadata": report], to: done())))
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(
            stub, fallbacks: [fallback(), fallback("openrouter/auto")], serverTools: [.webSearch(maximumResults: 3)],
            routing: OpenRouterRouting(order: ["Anthropic"], fallbackProviders: .disallowed, sort: .price),
            responseCache: OpenRouterResponseCache(timeToLive: .seconds(600)),
            options: OpenRouterOptions(autoRouter: .init(allowedModels: ["anthropic/*"]), includesRouterMetadata: true))
        return await ExactExchange(stub, LanguageModelSession(model: model)) { session, _ in
            try await session.respond(to: "Hi").usage
        }
    }

    /// A streamed answer that an error event ends partway, after the response's HTTP 200.
    static func errorMidStream() async -> ExactExchange {
        let failure: JSONValue = [
            "error": [
                "code": 502, "message": "Provider returned error",
                "metadata": ["provider_name": "Vendor", "error_type": "provider_overloaded"],
            ]
        ]
        let stub = HTTPStub(events(text("Partial "), failure))
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub)
        return await ExactExchange(stub, LanguageModelSession(model: model)) { session, lastSnapshot in
            try await stream(session.streamResponse(to: "Plan the week."), into: &lastSnapshot)
        }
    }

    /// A streamed answer whose stream stops before `[DONE]` and before any finish reason.
    static func cutOff() async -> ExactExchange {
        let stub = HTTPStub(unfinishedEvents(text("The plan")))
        let model: OpenRouterLanguageModel<Efforts.Unsupported> = model(stub)
        return await ExactExchange(stub, LanguageModelSession(model: model)) { session, lastSnapshot in
            try await stream(session.streamResponse(to: "Plan the week."), into: &lastSnapshot)
        }
    }
}

/// A rating whose stars have a range, which some hosts reject as a constraint of the schema.
@Generable
struct SoupRating {
    @Guide(description: "From 1 to 5", .range(1...5))
    var stars: Int

    var reason: String
}
