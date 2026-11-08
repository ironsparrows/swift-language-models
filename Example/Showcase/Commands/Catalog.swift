import Foundation
import FoundationModels
import OpenRouterLanguageModels
import UniformTypeIdentifiers

/// The typed catalog: every model OpenRouter listed when the catalog was generated, with its context size, output
/// limit and capabilities, offline and without a key.
///
/// Each catalog model is also a static member, such as `.anthropicClaudeHaiku5_5`, and `catalogModels` lists them all
/// for an app that lets people pick one.
struct Catalog: Command {
    let name = "catalog"
    let summary = "Browse the model catalog by capability, with context sizes and output limits"
    let usage = "[capability] [words]"
    let needsKey = false

    func run(_ arguments: [String]) async throws {
        let all = OpenRouterModel.catalogModels
        var models = all
        for word in arguments {
            if let capability = Capability(rawValue: word) {
                models = models.filter(capability.isSupported)
            } else {
                models = models.filter { $0.id.rawValue.localizedCaseInsensitiveContains(word) }
            }
        }

        print(Style.bold("Model".padded(to: 50) + "Context".padded(to: 9) + "Capabilities"))
        for model in models {
            let context = model.contextSize?.formatted(.number.notation(.compactName)) ?? "?"
            let capabilities = Capability.allCases.filter { $0.isSupported(by: model) }.map(\.rawValue)
            print(model.id.rawValue.padded(to: 50) + context.padded(to: 9) + capabilities.joined(separator: " "))
        }
        print(Style.dim("\n\(models.count) of \(all.count) models, by id. Context is the most tokens in."))
        if arguments.isEmpty {
            let capabilities = Capability.allCases.map(\.rawValue).joined(separator: ", ")
            print(Style.dim("Narrow it by capability (\(capabilities)) and by words in the id: `showcase catalog vision claude`."))
        }
    }

    enum Capability: String, CaseIterable {
        case tools, vision, reasoning, guided, images

        func isSupported(by model: OpenRouterModel<ContextOptions.ReasoningLevel>) -> Bool {
            switch self {
            case .tools: model.capabilities.contains(.toolCalling)
            case .vision: model.capabilities.contains(.vision)
            case .reasoning: model.capabilities.contains(.reasoning)
            case .guided: model.capabilities.contains(.guidedGeneration)
            case .images: model.supportsDataEntryType(.image)
            }
        }
    }
}
