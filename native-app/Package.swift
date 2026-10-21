// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HexcoreLink",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CLiana",
            path: "Sources/CLiana",
            sources: ["liana.c", "hidapi/mac/hid.c"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("hidapi/hidapi"),
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "HexcoreLink",
            dependencies: ["CLiana", "CSQLiteMC"],
            path: "Sources/HexcoreLink"
        ),
        .executableTarget(
            name: "LianaProbe",
            dependencies: ["CLiana"],
            path: "Sources/LianaProbe"
        ),
        .target(
            name: "CSQLiteMC",
            path: "Sources/CSQLiteMC",
            sources: ["sqlite3.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
            ]
        ),
        .executableTarget(
            name: "DbProbe",
            dependencies: ["CSQLiteMC"],
            path: "Sources/DbProbe"
        ),
    ]
)
