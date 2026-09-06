import Foundation

enum ApplicationListFormatter {
    static let maximumVisibleItemCount = 3

    static func processLabel(
        name: String,
        processIdentifier: Int32,
        allNames: [String]
    ) -> String {
        guard allNames.count(where: { $0 == name }) > 1 else {
            return name
        }
        return "\(name) — Process \(processIdentifier)"
    }

    static func summary(
        names: [String],
        emptyFallback: String
    ) -> String {
        guard !names.isEmpty else {
            return emptyFallback
        }
        var items = Array(names.prefix(maximumVisibleItemCount))
        let remainingCount = names.count - items.count
        if remainingCount > 0 {
            items.append(
                remainingCount == 1 ? "1 other" : "\(remainingCount) others"
            )
        }
        return ListFormatter.localizedString(byJoining: items)
    }
}
