// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Barik",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Barik", targets: ["Barik"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/gonzalezreal/swift-markdown-ui",
            exact: "2.4.1"
        ),
        .package(
            url: "https://github.com/dduan/TOMLDecoder",
            exact: "0.3.1"
        ),
    ],
    targets: [
        .executableTarget(
            name: "Barik",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ],
            path: "Barik",
            exclude: [
                "Info.plist",
                "Barik.entitlements",
                "Resources/Assets.xcassets",
                // String Catalogs need Xcode's xcstringstool to compile, which
                // ships only with full Xcode. Excluded for the CLT-only build;
                // NSLocalizedString falls back to the keys. See README.
                "Resources/Localizable.xcstrings",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
