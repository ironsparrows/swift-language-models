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
        .library(name: "LanguageModelsCore", targets: ["LanguageModelsCore"]),
        .library(name: "LanguageModels", targets: ["LanguageModels"]),
    ]
        + providers.map(\.product),
    dependencies: [
        // For tests only: no product depends on it, so it never reaches an app's code.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7")
    ],
    targets: [
        // The public contract every provider shares: the model protocol, details, efforts, configuration, attachments,
        // metadata, guide violations and the logging switch. A library that needs only the contract compiles no HTTP code.
        .target(
            name: "LanguageModelsCore",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LanguageModelsCoreTests",
            dependencies: ["LanguageModelsCore", "LanguageModelsTestSupport"],
            swiftSettings: swiftSettings
        ),
        // OpenAI's Chat Completions and Responses formats, which provider modules build on, and what they share: sending
        // requests, reading transcripts and streams, writing Foundation Models' channel. It re-exports the core and
        // declares nothing public of its own.
        .target(
            name: "LanguageModels",
            dependencies: ["LanguageModelsCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LanguageModelsTests",
            dependencies: ["LanguageModels", "LanguageModelsTestSupport"],
            swiftSettings: swiftSettings
        ),
        // What the test targets share: HTTP stubs, a loopback server, fixtures, exact exchanges, the checks every
        // provider has to pass, the snapshot strategy for request bodies and live-test tools.
        .target(
            name: "LanguageModelsTestSupport",
            dependencies: ["LanguageModelsCore", .product(name: "InlineSnapshotTesting", package: "swift-snapshot-testing")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "LanguageModelsTestSupportTests",
            dependencies: ["LanguageModelsTestSupport"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
        // Reads the providers' model lists into `Catalogs/`, and turns the catalogs into the Swift sources of the
        // `Generated/` folders.
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
        // Runs the generator's `fetch` and then its `render`, as `swift package plugin generate-model-catalog`.
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

// Each provider module is named `<Name>LanguageModels`, with its own library product and test target: one each for
// OpenRouter and OpenAI, and `OpenAICompatible` for any provider that speaks OpenAI's formats. Adding one here creates
// them; the module depends on `LanguageModels` and re-exports it.
var providers: [Provider] {
    [
        provider("OpenRouter"),
        provider("OpenAI"),
        provider("OpenAICompatible"),
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

func provider(_ name: String) -> Provider {
    Provider(
        name: name,
        targets: [
            .target(
                name: "\(name)LanguageModels",
                dependencies: ["LanguageModels"],
                swiftSettings: swiftSettings
            ),
            .testTarget(
                name: "\(name)LanguageModelsTests",
                dependencies: [.target(name: "\(name)LanguageModels"), "LanguageModelsTestSupport"],
                resources: [.copy("Fixtures")],
                swiftSettings: swiftSettings
            ),
        ]
    )
}
