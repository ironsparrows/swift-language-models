// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-language-models",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .visionOS(.v27),
        .watchOS(.v27),
    ],
    products: [
        .library(name: "LanguageModels", targets: ["LanguageModels"])
    ]
        + providers.map(\.product),
    dependencies: [
        // For tests only: no product depends on it, so it never reaches an app's code.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7")
    ],
    targets: [
        .target(
            name: "LanguageModels",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LanguageModelsTests",
            dependencies: ["LanguageModels", "LanguageModelsTestSupport"],
            swiftSettings: swiftSettings
        ),
        // What the API formats share and providers never name: reading transcripts and streams, assembling tool calls,
        // sending an answer to Foundation Models' channel, opening a stream with the portable-schema retry, the changes a
        // request makes and the limits of OpenAI's formats. Provider modules don't depend on it.
        .target(
            name: "APIFormat",
            dependencies: ["LanguageModels"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "APIFormatTests",
            dependencies: ["APIFormat", "LanguageModelsTestSupport"],
            swiftSettings: swiftSettings
        ),
        // OpenAI's Chat Completions format, which provider modules build on. It isn't a product, so apps never import it.
        .target(
            name: "ChatCompletionsAPI",
            dependencies: ["LanguageModels", "APIFormat"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ChatCompletionsAPITests",
            dependencies: ["ChatCompletionsAPI", "APIFormat", "LanguageModelsTestSupport"],
            swiftSettings: swiftSettings
        ),
        // OpenAI's Responses format, which provider modules build on. It isn't a product, so apps never import it.
        .target(
            name: "ResponsesAPI",
            dependencies: ["LanguageModels", "APIFormat"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ResponsesAPITests",
            dependencies: ["ResponsesAPI", "APIFormat", "LanguageModelsTestSupport"],
            swiftSettings: swiftSettings
        ),
        // What the test targets share: HTTP stubs, fixtures, canonical JSON, exact exchanges, the snapshot strategy for
        // request bodies and live-test tools.
        .target(
            name: "LanguageModelsTestSupport",
            dependencies: ["LanguageModels", .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LanguageModelsTestSupportTests",
            dependencies: ["LanguageModelsTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "ModelCatalogGenerator",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ModelCatalogGeneratorTests",
            dependencies: ["ModelCatalogGenerator", "LanguageModelsTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
        .plugin(
            name: "GenerateModelCatalog",
            capability: .command(
                intent: .custom(
                    verb: "generate-model-catalog",
                    description: "Download the providers' model lists and regenerate the typed model data"
                ),
                permissions: [
                    .allowNetworkConnections(scope: .all(ports: [443]), reason: "Download the providers' model lists"),
                    .writeToPackageDirectory(reason: "Update Catalogs/ and the generated Swift sources"),
                ]
            ),
            dependencies: ["ModelCatalogGenerator"]
        ),
    ]
        + providers.flatMap(\.targets),
    swiftLanguageModes: [.v6]
)

nonisolated var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("ImmutableWeakCaptures"),
        .strictMemorySafety(),
    ]
}

// Each provider is a module named `<Name>LanguageModels`, with its own library product and test target. Adding a
// provider here creates them; the module depends on `LanguageModels` and on the API formats it uses, and re-exports
// only `LanguageModels`.
var providers: [Provider] {
    [
        provider("OpenRouter", uses: ["ChatCompletionsAPI"]),
        provider("OpenAI", uses: ["ResponsesAPI"]),
    ]
}

/// A provider module, its library product and its test target.
struct Provider {
    let name: String
    let targets: [Target]

    var product: Product {
        .library(name: "\(name)LanguageModels", targets: ["\(name)LanguageModels"])
    }
}

func provider(_ name: String, uses formats: [String]) -> Provider {
    let formatDependencies = formats.map { Target.Dependency.target(name: $0) }
    return Provider(
        name: name,
        targets: [
            .target(
                name: "\(name)LanguageModels",
                dependencies: ["LanguageModels"] + formatDependencies,
                swiftSettings: swiftSettings
            ),
            .testTarget(
                name: "\(name)LanguageModelsTests",
                dependencies: [.target(name: "\(name)LanguageModels"), "APIFormat", "LanguageModelsTestSupport"] + formatDependencies,
                resources: [.copy("Fixtures")],
                swiftSettings: swiftSettings
            ),
        ]
    )
}
