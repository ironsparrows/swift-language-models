import Foundation
import FoundationModels
import LanguageModels
import LanguageModelsTestSupport
import Testing

@testable import OpenAICompatibleLanguageModels

extension PresetTests {
    @Suite("Cache key")
    struct CacheKey {
        @Test(arguments: [
            (OpenAICompatibleProvider.xAI, true), (.mistral, true), (.gemini, false), (.groq, false), (.deepSeek, false),
            (.ollama, false), (.lmStudio, false), (.vLLM, false),
        ])
        func `a cache key goes only to a preset whose provider takes it`(provider: OpenAICompatibleProvider, sends: Bool) async throws {
            let stub = HTTPStub(provider.format == .responses ? events(textDelta("Hi"), completed()) : chunks(text("Hi"), finish()))
            let options = OpenAICompatibleOptions(cacheKey: .named("coach"))

            _ = try await LanguageModelSession(model: model(stub, on: provider.at(stub.baseURL), options: options)).respond(to: "Hi")

            #expect(try body(stub)["prompt_cache_key"] == (sends ? "coach" : nil))
        }
    }
}
