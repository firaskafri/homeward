import AppKit
import SwiftUI

enum HomewardSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
}

enum HomewardTone: Equatable {
    case ready
    case attention
    case rest
    case critical
    case neutral

    var color: Color {
        switch self {
        case .ready:
            Color(nsColor: .systemTeal)
        case .attention:
            Color(nsColor: .systemOrange)
        case .rest:
            Color(nsColor: .systemIndigo)
        case .critical:
            Color(nsColor: .systemRed)
        case .neutral:
            Color.secondary
        }
    }
}

enum HomewardMetrics {
    static let cardCornerRadius: CGFloat = 14
    static let compactCornerRadius: CGFloat = 10
    static let contentMaxWidth: CGFloat = 920
}
