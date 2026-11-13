// swift-tools-version:6.2

import PackageDescription

let package = Package(
    name: "AwesomeWS",
    platforms: [
       .macOS(.v10_15)
    ],
    products: [
        .library(name: "WS", targets: ["WS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.0.0")
    ],
    targets: [
        .target(name: "WS", dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            .product(name: "WebSocketKit", package: "websocket-kit"),
        ]),
        .testTarget(name: "WSTests", dependencies: [
            .target(name: "WS"),
            .product(name: "Vapor", package: "vapor"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOEmbedded", package: "swift-nio"),
            .product(name: "NIOWebSocket", package: "swift-nio"),
            .product(name: "WebSocketKit", package: "websocket-kit"),
        ]),
    ]
)
