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

var failures: [String] = []

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

        for heading in headings where !contents.contains("// \(heading):") {
            failures.append("\(relativePath): missing file documentation heading '\(heading)'")
        }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isTestMarker = trimmed.hasPrefix("@Test")
                || trimmed.hasPrefix("func test")
            let isSuiteMarker = trimmed.hasPrefix("@Suite")
                || trimmed.hasPrefix("final class")
            guard isTestMarker || isSuiteMarker else {
                continue
            }

            let start = max(0, index - 10)
            let context = lines[start..<index].joined(separator: "\n")
            for heading in headings where !context.contains("/// \(heading):") {
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
