import AppKit

@MainActor
enum HomewardPanelFactory {
    static func make(
        title: String,
        size: NSSize,
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
        if floatsAutomatically {
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        return panel
    }
}
