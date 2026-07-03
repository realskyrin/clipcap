// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "clipcap",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "clipcap", targets: ["clipcap"]),
        .executable(name: "ClipcapShareExtension", targets: ["ClipcapShareExtension"])
    ],
    targets: [
        .executableTarget(
            name: "clipcap",
            path: "clipcap",
            exclude: ["App/Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Vision"),
                .linkedFramework("VisionKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ImageIO"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
                .linkedLibrary("z"),
            ]
        ),
        .executableTarget(
            name: "ClipcapShareExtension",
            path: "clipcap-share-extension",
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        )
    ]
)
