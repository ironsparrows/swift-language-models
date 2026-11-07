import Foundation
import LanguageModels
import Testing

@Suite("Same-host redirects")
struct SameHostRedirectsTests {
    @Test(arguments: [
        ("https://api.example.com/v1/chat", "https://api.example.com/v2/chat", true),
        ("https://api.example.com/v1/chat", "https://API.Example.com/v2/chat", true),
        ("https://api.example.com/v1/chat", "https://api.example.com:443/v2/chat", true),
        ("https://api.example.com/v1/chat", "https://evil.example.org/v1/chat", false),
        ("https://api.example.com/v1/chat", "http://api.example.com/v1/chat", false),
        ("https://api.example.com/v1/chat", "https://api.example.com:8443/v1/chat", false),
    ])
    func `a redirect is followed only to the same scheme, host and port`(from: String, to: String, isFollowed: Bool) async throws {
        let followed = try await redirect(from: URLRequest(url: try #require(URL(string: from))), to: to)

        #expect((followed != nil) == isFollowed)
    }

    @Test func `a followed redirect keeps the request's credentials`() async throws {
        var original = URLRequest(url: try #require(URL(string: "https://api.example.com/v1/chat")))
        original.setValue("Bearer key", forHTTPHeaderField: "Authorization")

        let followed = try await redirect(from: original, to: "https://api.example.com/v2/chat")

        #expect(followed?.value(forHTTPHeaderField: "Authorization") == "Bearer key")
    }

    private func redirect(from original: URLRequest, to target: String) async throws -> URLRequest? {
        let url = try #require(original.url)
        let task = URLSession.shared.dataTask(with: original)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: nil))
        return await SameHostRedirects().urlSession(
            .shared,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: try #require(URL(string: target)))
        )
    }
}
