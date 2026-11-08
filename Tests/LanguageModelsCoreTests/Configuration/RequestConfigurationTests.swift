import LanguageModelsCore
import Testing

@Suite("Request configuration")
struct RequestConfigurationTests {
    @Test func `the standard retries are two, from half a second, with a server wait of up to 2 minutes`() {
        #expect(RequestRetries.standard == RequestRetries(limit: 2, initialDelay: .milliseconds(500), longestServerWait: .seconds(120)))
        #expect(RequestRetries.disabled.limit == 0)
    }

    @Test func `the standard image encoding keeps 2,048 pixels at a quality of 0.85`() {
        #expect(ImageEncoding.standard == ImageEncoding(maximumSide: 2_048, quality: 0.85))
    }
}
