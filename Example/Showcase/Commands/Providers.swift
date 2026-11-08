import Foundation
import FoundationModels
import OpenRouterLanguageModels

/// The hosts that serve a model, live from OpenRouter: each endpoint's tier, prices, latency and uptime.
///
/// `endpoints()` needs no key. With one, OpenRouter adds each endpoint's latency, so the command sends the key when
/// there is one. Each row's tag goes in `OpenRouterRouting(order:)` to send requests to that endpoint.
struct Providers: Command {
    let name = "providers"
    let summary = "List the providers that serve a model, live, with their tier, prices, latency and uptime"
    let usage = "[model-id]"
    let needsKey = false

    func run(_ arguments: [String]) async throws {
        let id = OpenRouterModelID(rawValue: arguments.first ?? "anthropic/claude-haiku-5.5")
        let model =
            OpenRouterModel(catalogID: id)
            ?? OpenRouterModel(id: id, displayName: id.rawValue, supportedParameters: [])
        let key = openRouterKey()

        let providers = try await model.endpoints(auth: key.isEmpty ? nil : .apiKey { key })

        guard !providers.isEmpty else {
            print("OpenRouter lists no providers for \(id). An alias, such as ~anthropic/claude-haiku-latest, has none of its own.")
            return
        }
        let columns = [("Provider", 30), ("Tier", 10), ("In", 11), ("Out", 11), ("Latency", 10), ("Uptime", 9)]
        print(Style.bold(columns.map { $0.0.padded(to: $0.1) }.joined() + "Context"))
        for provider in providers.sorted(by: Self.cheaperFirst) {
            let tier = provider.serviceTier?.rawValue ?? "standard"
            let prompt = provider.pricing.map { Self.perMillion($0.prompt) } ?? "?"
            let completion = provider.pricing.map { Self.perMillion($0.completion) } ?? "?"
            let latency = provider.latencyLast30Minutes?.p50.map { "\(Int($0 / .milliseconds(1))) ms" } ?? "-"
            let uptime = provider.uptimeLastDay.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))%" } ?? "-"
            let context = provider.contextSize?.formatted(.number.notation(.compactName)) ?? "?"
            let row =
                provider.tag.rawValue.padded(to: 30) + tier.padded(to: 10) + prompt.padded(to: 11) + completion.padded(to: 11)
                + latency.padded(to: 10) + uptime.padded(to: 9) + context
            print((provider.status ?? 0) < 0 ? Style.red(row) : row)
        }
        var notes = [
            "\(providers.count) endpoints of \(id), cheapest first. In and out are US dollars per million tokens.",
            "Latency is the median time to the first token over the last 30 minutes; uptime covers the last day.",
        ]
        if key.isEmpty {
            notes.append("OpenRouter reports latency only to a call with an API key.")
        }
        if providers.contains(where: { ($0.status ?? 0) < 0 }) {
            notes.append("Red rows are endpoints that OpenRouter sees as degraded or down.")
        }
        notes.append("A provider's tag goes in OpenRouterRouting(order:) to send requests there.")
        print(Style.dim("\n" + notes.joined(separator: "\n")))
    }

    /// Whether one endpoint's prompt price is lower than another's, with an endpoint priced per request last.
    private static func cheaperFirst(_ first: OpenRouterEndpoint, _ second: OpenRouterEndpoint) -> Bool {
        switch (first.pricing?.prompt, second.pricing?.prompt) {
        case (let first?, let second?): first < second
        case (_?, nil): true
        default: false
        }
    }

    /// A price per token as US dollars per million tokens, such as `$0.10`.
    private static func perMillion(_ price: Decimal) -> String {
        (price * 1_000_000).formatted(.currency(code: "USD").precision(.fractionLength(2...3)))
    }
}
