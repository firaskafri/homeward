#!/usr/bin/env swift

import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let testDirectories = [
    "Tests",
    "HomewardAppTests",
    "HomewardUITests",
]
let headings = [
    "1 - Name",
    "2 - Description",
    "3 - Assumptions",
    "4 - Expectations",
]
let documentationPrefix = "/// "

var failures: [String] = []

func documentationBlock(
    before lineIndex: Int,
    in lines: [String],
    skippingAttributes: Bool
) -> String {
    var cursor = lineIndex - 1
    while cursor >= 0 {
        let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || (skippingAttributes && trimmed.hasPrefix("@")) {
            cursor -= 1
            continue
        }
        break
    }

    var documentation: [String] = []
    while cursor >= 0 {
        let trimmed = lines[cursor].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(documentationPrefix) else {
            break
        }
        documentation.append(trimmed)
        cursor -= 1
    }
    return documentation.reversed().joined(separator: "\n")
}

for relativeDirectory in testDirectories {
    let directory = root.appendingPathComponent(relativeDirectory)
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: nil
    ) else {
        failures.append("Missing test directory: \(relativeDirectory)")
        continue
    }

    for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
        let relativePath = fileURL.path.replacingOccurrences(
            of: root.path + "/",
            with: ""
        )
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.components(separatedBy: .newlines)

        let fileDocumentation = lines.prefix(30).filter {
            $0.trimmingCharacters(in: .whitespaces)
                .hasPrefix("// ")
        }.joined(separator: "\n")
        for heading in headings
            where !fileDocumentation.contains("// \(heading):") {
            failures.append("\(relativePath): missing file documentation heading '\(heading)'")
        }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isTestMarker = trimmed.hasPrefix("@Test")
                || trimmed.range(
                    of: #"^func\s+test"#,
                    options: .regularExpression
                ) != nil
            let isSuiteMarker = trimmed.hasPrefix("@Suite")
                || (trimmed.contains("class ")
                    && trimmed.contains(": XCTestCase"))
            guard isTestMarker || isSuiteMarker else {
                continue
            }

            let context = documentationBlock(
                before: index,
                in: lines,
                skippingAttributes: !trimmed.hasPrefix("@")
            )
            for heading in headings
                where !context.contains("\(documentationPrefix)\(heading):") {
                let kind = isTestMarker ? "test" : "suite/type"
                failures.append(
                    "\(relativePath):\(index + 1): \(kind) missing documentation heading '\(heading)'"
                )
            }
        }
    }
}

if failures.isEmpty {
    print("Test documentation verified.")
    exit(EXIT_SUCCESS)
}

for failure in failures {
    FileHandle.standardError.write(Data((failure + "\n").utf8))
}
exit(EXIT_FAILURE)
