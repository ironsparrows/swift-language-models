import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenRouterLanguageModels

/// The keys of the router's report.
private let routingKeys = [
    OpenRouterMetadataKey.routingStrategy, OpenRouterMetadataKey.routingAttempt, OpenRouterMetadataKey.routingAttempts,
    OpenRouterMetadataKey.routingEndpoints, OpenRouterMetadataKey.routingPipeline, OpenRouterMetadataKey.region,
    OpenRouterMetadataKey.generationTime,
]

extension OpenRouterMetadataTests {
    @Suite("Router")
    struct Router {
        @Test(arguments: [true, false])
        func `every request asks for router metadata, since only it shows a guardrail's block`(includes: Bool) async throws {
            let stub = HTTPStub(events(text("Hi"), done()))
            let options = OpenRouterOptions(includesRouterMetadata: includes)

            _ = try await LanguageModelSession(model: model(stub, options: options)).respond(to: "Hi")

            #expect(try #require(stub.requests.first).request.value(forHTTPHeaderField: "X-OpenRouter-Metadata") == "enabled")
        }

        @Test func `the router's report stays out of the answer unless the options include it`() async throws {
            let report: JSONValue = ["strategy": "direct", "region": "iad"]
            let stub = HTTPStub(events(text("Hi"), adding(["openrouter_metadata": report], to: done())))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            let metadata = try lastResponse(of: response).metadata
            #expect(routingKeys.allSatisfy { metadata[$0] == nil })
        }

        @Test func `the router's report on the last chunk reaches the answer's entry`() async throws {
            let report: JSONValue = [
                "requested": "vendor/model",
                "strategy": "fallback",
                "region": "iad",
                "summary": "available=2, selected=Other",
                "attempt": 2,
                "is_byok": false,
                "generation_time": 2_016,
                "endpoints": [
                    "total": 3,
                    "available": [
                        ["provider": "Vendor", "model": "vendor/model", "selected": false],
                        ["provider": "Other", "model": "vendor/model", "selected": true],
                    ],
                ],
                "attempts": [
                    ["provider": "Vendor", "model": "vendor/model", "status": 503],
                    ["provider": "Other", "model": "vendor/model", "status": 200],
                ],
                "pipeline": [
                    [
                        "type": "guardrail", "name": "content-filter", "summary": "PII redacted", "guardrail_id": "grd_1",
                        "data": ["flagged": true],
                    ],
                    ["type": "a_future_stage", "name": "new-plugin"],
                ],
                "params": ["version_group": "vendor/model"],
            ]
            let stub = HTTPStub(events(text("Hi"), adding(["openrouter_metadata": report], to: done())))
            let options = OpenRouterOptions(includesRouterMetadata: true)

            let response = try await LanguageModelSession(model: model(stub, options: options)).respond(to: "Hi")

            let metadata = try lastResponse(of: response).metadata
            #expect(metadataString(metadata, OpenRouterMetadataKey.routingStrategy) == "fallback")
            #expect(try metadataJSON(metadata, OpenRouterMetadataKey.routingAttempt) == 2)
            #expect(
                try metadataJSON(metadata, OpenRouterMetadataKey.routingAttempts) == [
                    ["provider": "Vendor", "model": "vendor/model", "status": 503],
                    ["provider": "Other", "model": "vendor/model", "status": 200],
                ]
            )
            #expect(
                try metadataJSON(metadata, OpenRouterMetadataKey.routingEndpoints) == [
                    ["provider": "Vendor", "model": "vendor/model", "selected": false],
                    ["provider": "Other", "model": "vendor/model", "selected": true],
                ]
            )
            #expect(
                try metadataJSON(metadata, OpenRouterMetadataKey.routingPipeline) == [
                    ["type": "guardrail", "name": "content-filter", "summary": "PII redacted"],
                    ["type": "a_future_stage", "name": "new-plugin", "summary": .null],
                ]
            )
            #expect(metadataString(metadata, OpenRouterMetadataKey.region) == "iad")
            #expect(metadataNumber(metadata, OpenRouterMetadataKey.generationTime) == 2.016)
            #expect(response.usage.metadata[OpenRouterMetadataKey.routingStrategy] == nil)
        }

        @Test func `a report with fields left out or unknown still ends the answer, with only the fields it has`() async throws {
            let report: JSONValue = ["requested": "vendor/model", "strategy": "direct", "region": .null, "a_future_field": ["x": 1]]
            let stub = HTTPStub(events(text("Hi"), adding(["openrouter_metadata": report], to: done())))
            let options = OpenRouterOptions(includesRouterMetadata: true)

            let response = try await LanguageModelSession(model: model(stub, options: options)).respond(to: "Hi")

            #expect(response.content == "Hi")
            let metadata = try lastResponse(of: response).metadata
            #expect(metadataString(metadata, OpenRouterMetadataKey.routingStrategy) == "direct")
            #expect(routingKeys.dropFirst().allSatisfy { metadata[$0] == nil })
        }

        @Test func `an answer without a report carries no routing keys`() async throws {
            let stub = HTTPStub(events(text("Hi"), done()))

            let response = try await LanguageModelSession(model: model(stub)).respond(to: "Hi")

            let metadata = try lastResponse(of: response).metadata
            #expect(routingKeys.allSatisfy { metadata[$0] == nil })
        }
    }
}
