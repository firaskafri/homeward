import AppKit
import HomewardCore
import SwiftUI

struct HomewardCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(
        padding: CGFloat = HomewardSpacing.large,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(
                    cornerRadius: HomewardMetrics.cardCornerRadius,
                    style: .continuous
                )
                .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: HomewardMetrics.cardCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    Color.primary.opacity(
                        colorSchemeContrast == .increased ? 0.28 : 0.09
                    )
                )
            }
    }
}

struct HomewardStatusLabel: View {
    let title: String
    let symbol: String
    let tone: HomewardTone

    var body: some View {
        HStack(spacing: HomewardSpacing.xSmall) {
            Image(systemName: symbol)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.primary)
        }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, HomewardSpacing.small)
            .padding(.vertical, HomewardSpacing.xSmall)
            .background(
                tone.color.opacity(0.12),
                in: Capsule(style: .continuous)
            )
    }
}

struct HomewardApplicationSummary: View {
    let applications: [SelectedApplication]

    private var visibleApplications: ArraySlice<SelectedApplication> {
        applications.prefix(3)
    }

    private var names: String {
        let visibleNames = visibleApplications.map(\.displayName)
        let remainingCount = applications.count - visibleNames.count
        if remainingCount > 0 {
            return visibleNames.joined(separator: ", ") + " +\(remainingCount)"
        }
        return visibleNames.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: HomewardSpacing.medium) {
            if applications.isEmpty {
                Image(systemName: "app.dashed")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
            } else {
                HStack(spacing: -8) {
                    ForEach(Array(visibleApplications.enumerated()), id: \.element.id) {
                        item in
                        let (index, application) = item
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.bundlePath))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .padding(2)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.12))
                            }
                            .zIndex(Double(visibleApplications.count - index))
                            .accessibilityHidden(true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(applications.isEmpty ? "No work apps selected" : names)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(applications.count == 1 ? "1 selected app" : "\(applications.count) selected apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
