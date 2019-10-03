// swift-tools-version:5.1

import PackageDescription

let package = Package(
  name: "Uniflow",
  platforms: [
    .iOS(.v11)
  ],
  products: [
    .library(name: "Uniflow", targets: ["Uniflow"]),
  ],
  dependencies: [
    .package(url: "https://github.com/ReactiveX/RxSwift.git", .upToNextMajor(from: "5.0.1")),
    .package(url: "https://github.com/nesium/NSMFoundation.git", .upToNextMajor(from: "1.0.0"))
  ],
  targets: [
    .target(name: "Uniflow", dependencies: ["RxSwift", "NSMFoundation"]), 
    .testTarget(name: "UniflowTests", dependencies: ["Uniflow"])
  ]
)
