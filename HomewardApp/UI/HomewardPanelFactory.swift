import AppKit
import SwiftUI

@MainActor
enum HomewardPanelFactory {
    static func make(
        title: String,
        size: NSSize,
        minimumSize: NSSize? = nil,
        resizable: Bool = false,
        floatsAutomatically: Bool = false
    ) -> NSPanel {
        var style: NSWindow.StyleMask = [.titled, .closable, .utilityWindow]
        if resizable {
            style.insert(.resizable)
        }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.tabbingMode = .disallowed
        panel.isRestorable = false
        if let minimumSize {
            panel.contentMinSize = minimumSize
        }
        if floatsAutomatically {
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        return panel
    }
}

struct HomewardPanelHeader: View {
    let title: String
    let message: String
    let systemImage: String
    let tone: HomewardTone

    init(
        title: String,
        message: String,
        systemImage: String,
        tone: HomewardTone = .neutral
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: HomewardSpacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 40, height: 40)
                .background(
                    tone.color.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: HomewardMetrics.compactCornerRadius,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: HomewardSpacing.xSmall) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
