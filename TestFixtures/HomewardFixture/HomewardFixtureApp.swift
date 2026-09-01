import AppKit
import SwiftUI

@main
struct HomewardFixtureApp: App {
    @NSApplicationDelegateAdaptor(FixtureDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "testtube.2")
                    .font(.largeTitle)
                Text("Homeward Fixture")
                    .font(.title2)
                Text(appDelegate.mode.description)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(minWidth: 320, minHeight: 180)
        }
    }
}

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    enum Mode: String {
        case immediate
        case delayed
        case refuse

        var description: String {
            switch self {
            case .immediate:
                "Quits immediately"
            case .delayed:
                "Quits after a short delay"
            case .refuse:
                "Rejects normal quit"
            }
        }
    }

    let mode = Mode(
        rawValue: ProcessInfo.processInfo.environment["HOMEWARD_FIXTURE_MODE"] ?? ""
    ) ?? .immediate

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch mode {
        case .immediate:
            return .terminateNow
        case .refuse:
            return .terminateCancel
        case .delayed:
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}
