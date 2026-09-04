#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct AssetCatalog: Decodable {
    let images: [IconSlot]
}

private struct IconSlot: Codable, Equatable {
    let filename: String
    let idiom: String
    let scale: String
    let size: String
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private let outputDirectory = URL(
    fileURLWithPath: repositoryRoot.path
).appendingPathComponent(
    "HomewardApp/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)

private let requiredSlots = [
    IconSlot(filename: "homeward-16.png", idiom: "mac", scale: "1x", size: "16x16"),
    IconSlot(filename: "homeward-32.png", idiom: "mac", scale: "2x", size: "16x16"),
    IconSlot(filename: "homeward-32.png", idiom: "mac", scale: "1x", size: "32x32"),
    IconSlot(filename: "homeward-64.png", idiom: "mac", scale: "2x", size: "32x32"),
    IconSlot(filename: "homeward-128.png", idiom: "mac", scale: "1x", size: "128x128"),
    IconSlot(filename: "homeward-256.png", idiom: "mac", scale: "2x", size: "128x128"),
    IconSlot(filename: "homeward-256.png", idiom: "mac", scale: "1x", size: "256x256"),
    IconSlot(filename: "homeward-512.png", idiom: "mac", scale: "2x", size: "256x256"),
    IconSlot(filename: "homeward-512.png", idiom: "mac", scale: "1x", size: "512x512"),
    IconSlot(filename: "homeward-1024.png", idiom: "mac", scale: "2x", size: "512x512"),
]
private let sizes = [16, 32, 64, 128, 256, 512, 1024]
private let arguments = Array(CommandLine.arguments.dropFirst())
private let unsupportedArguments = arguments.filter { $0 != "--check" }
guard unsupportedArguments.isEmpty else {
    throw CocoaError(
        .fileReadUnsupportedScheme,
        userInfo: [
            NSLocalizedDescriptionKey:
                "Unsupported arguments: \(unsupportedArguments.joined(separator: ", "))"
        ]
    )
}
private let checkOnly = arguments.contains("--check")

private let manifestURL = outputDirectory.appendingPathComponent("Contents.json")
private let manifest = try JSONDecoder().decode(
    AssetCatalog.self,
    from: Data(contentsOf: manifestURL)
)
guard manifest.images == requiredSlots else {
    throw RendererError.manifestMismatch(manifestURL.path)
}

private func makeColor(
    _ red: CGFloat,
    _ green: CGFloat,
    _ blue: CGFloat,
    _ alpha: CGFloat = 1
) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

private func renderIcon(size: Int) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let tile = CGPath(
        roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
        cornerWidth: 224,
        cornerHeight: 224,
        transform: nil
    )
    context.addPath(tile)
    context.clip()

    guard let background = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            makeColor(43 / 255, 54 / 255, 82 / 255),
            makeColor(23 / 255, 30 / 255, 49 / 255),
        ] as CFArray,
        locations: [0, 1]
    ) else {
        throw RendererError.gradientCreationFailed
    }
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 64, y: 960),
        end: CGPoint(x: 960, y: 64),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    guard let glow = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            makeColor(249 / 255, 161 / 255, 68 / 255, 0.46),
            makeColor(249 / 255, 161 / 255, 68 / 255, 0),
        ] as CFArray,
        locations: [0, 1]
    ) else {
        throw RendererError.gradientCreationFailed
    }
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: 512, y: 480),
        startRadius: 10,
        endCenter: CGPoint(x: 512, y: 480),
        endRadius: 328,
        options: []
    )

    context.resetClip()
    let border = CGPath(
        roundedRect: CGRect(x: 72, y: 72, width: 880, height: 880),
        cornerWidth: 216,
        cornerHeight: 216,
        transform: nil
    )
    context.addPath(border)
    context.setStrokeColor(makeColor(238 / 255, 243 / 255, 255 / 255, 0.3))
    context.setLineWidth(8)
    context.strokePath()

    let roof = CGMutablePath()
    roof.move(to: CGPoint(x: 248, y: 568))
    roof.addLine(to: CGPoint(x: 512, y: 792))
    roof.addLine(to: CGPoint(x: 776, y: 568))
    context.addPath(roof)
    context.setStrokeColor(makeColor(247 / 255, 249 / 255, 255 / 255))
    context.setLineWidth(64)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    let walls = CGMutablePath()
    walls.move(to: CGPoint(x: 296, y: 584))
    walls.addLine(to: CGPoint(x: 296, y: 400))
    walls.addLine(to: CGPoint(x: 728, y: 400))
    walls.addLine(to: CGPoint(x: 728, y: 584))
    context.addPath(walls)
    context.setStrokeColor(makeColor(247 / 255, 249 / 255, 255 / 255))
    context.setLineWidth(64)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    let threshold = CGPath(
        roundedRect: CGRect(x: 464, y: 328, width: 96, height: 176),
        cornerWidth: 24,
        cornerHeight: 24,
        transform: nil
    )
    context.addPath(threshold)
    context.setFillColor(makeColor(249 / 255, 161 / 255, 68 / 255))
    context.fillPath()

    let output = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(
              output,
              UTType.png.identifier as CFString,
              1,
              nil
          ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return output as Data
}

for size in sizes {
    let outputURL = outputDirectory.appendingPathComponent("homeward-\(size).png")
    let renderedIcon = try renderIcon(size: size)
    if checkOnly {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RendererError.missingIcon(outputURL.path)
        }
        let existingIcon = try Data(contentsOf: outputURL)
        guard existingIcon == renderedIcon else {
            throw RendererError.staleIcon(outputURL.path)
        }
    } else {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try renderedIcon.write(to: outputURL, options: .atomic)
    }
}

private enum RendererError: Error {
    case gradientCreationFailed
    case manifestMismatch(String)
    case missingIcon(String)
    case staleIcon(String)
}
