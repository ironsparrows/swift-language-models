import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// The response cache's headers, with whether they report a hit, the age in seconds and the source id.
private let cacheReports: [([String: String], OpenRouterResponseCache.Status?, Int?, String?)] = [
    (
        ["X-OpenRouter-Cache-Status": "HIT", "X-OpenRouter-Cache-Age": "12", "X-OpenRouter-Cache-Source-Id": "gen-abc123"],
        .hit, 12, "gen-abc123"
    ),
    (["X-OpenRouter-Cache-Status": "MISS"], .miss, nil, nil),
    (["X-OpenRouter-Cache-Status": "bypass"], "BYPASS", nil, nil),
    ([:], nil, nil, nil),
]

extension OpenRouterMetadataTests {
    @Suite("Response")
    struct Response {
        @Test func `the facts of an answer reach its response entry as typed values`() async throws {
            let stub = HTTPStub(events(text("Hi"), adding(["service_tier": "flex"], to: done("length"))))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            let metadata = try lastResponse(of: response).openRouter
            #expect(metadata.model == "vendor/model")
            #expect(metadata.provider == "Vendor")
            #expect(metadata.responseID == "gen-1")
            #expect(metadata.finishReason == .length)
            #expect(metadata.serviceTier == .flex)
            #expect(metadata.citations.isEmpty)
            #expect(metadata.responseCacheStatus == nil)
            #expect(metadata.routingStrategy == nil)
            #expect(metadata.routingAttempts.isEmpty)
            #expect(metadata.generationTime == nil)
        }

        @Test func `the router's report reaches the response entry as typed values`() async throws {
            let report: JSONValue = [
                "strategy": "fallback",
                "region": "iad",
                "attempt": 2,
                "generation_time": 2_016,
                "endpoints": [
                    "available": [
                        ["provider": "Vendor", "model": "vendor/model", "selected": false],
                        ["provider": "Other", "model": "vendor/model", "selected": true],
                    ]
                ],
                "attempts": [
                    ["provider": "Vendor", "model": "vendor/model", "status": 503],
                    ["provider": "Other", "model": "vendor/model", "status": 200],
                ],
                "pipeline": [
                    ["type": "guardrail", "name": "content-filter", "summary": "PII redacted"],
                    ["type": "a_future_stage", "name": "new-plugin"],
                ],
            ]
            let stub = HTTPStub(events(text("Hi"), adding(["openrouter_metadata": report], to: done())))
            let options = OpenRouterOptions(includesRouterMetadata: true)

            let response = try await LanguageModelSession(model: model(stub, options: options)).respond(to: "Hi")

            let metadata = try lastResponse(of: response).openRouter
            #expect(metadata.routingStrategy == .fallback)
            #expect(metadata.routingAttempt == 2)
            #expect(metadata.routingAttempts.map(\.provider) == ["Vendor", "Other"])
            #expect(metadata.routingAttempts.map(\.model) == ["vendor/model", "vendor/model"])
            #expect(metadata.routingAttempts.map(\.status) == [503, 200])
            #expect(metadata.routingEndpoints.map(\.provider) == ["Vendor", "Other"])
            #expect(metadata.routingEndpoints.map(\.isSelected) == [false, true])
            #expect(metadata.routingPipeline.map(\.kind) == [.guardrail, "a_future_stage"])
            #expect(metadata.routingPipeline.map(\.plugin) == ["content-filter", "new-plugin"])
            #expect(metadata.routingPipeline.map(\.summary) == ["PII redacted", nil])
            #expect(metadata.region == "iad")
            #expect(metadata.generationTime == .milliseconds(2_016))
        }

        @Test(arguments: cacheReports)
        func `what the response cache did reaches the response entry as typed values`(
            headers: [String: String],
            status: OpenRouterResponseCache.Status?,
            ageInSeconds: Int?,
            sourceID: String?
        ) async throws {
            let stub = HTTPStub(events(headers: headers, text("Hi"), done()))

            let response = try await LanguageModelSession(model: model(stub, responseCache: OpenRouterResponseCache())).respond(to: "Hi")

            let metadata = try lastResponse(of: response).openRouter
            #expect(metadata.responseCacheStatus == status)
            #expect(metadata.responseCacheAge == ageInSeconds.map { .seconds($0) })
            #expect(metadata.responseCacheSourceID == sourceID)
        }

        @Test func `a response entry without metadata has no facts`() {
            let metadata = Transcript.Response(segments: []).openRouter

            #expect(metadata.model == nil)
            #expect(metadata.provider == nil)
            #expect(metadata.responseID == nil)
            #expect(metadata.finishReason == nil)
            #expect(metadata.serviceTier == nil)
            #expect(metadata.citations.isEmpty)
            #expect(metadata.responseCacheStatus == nil)
            #expect(metadata.responseCacheAge == nil)
            #expect(metadata.routingAttempt == nil)
            #expect(metadata.routingEndpoints.isEmpty)
            #expect(metadata.routingPipeline.isEmpty)
            #expect(metadata.region == nil)
        }
    }
}
