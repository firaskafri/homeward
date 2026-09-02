import AppKit
import SwiftUI

@main
struct HomewardApp: App {
    @StateObject private var model: AppModel

    init() {
        let instance: AppModel
        do {
            instance = try AppModel.makeDefault()
        } catch {
            fatalError("Homeward could not initialize local storage: \(error)")
        }
        _model = StateObject(wrappedValue: instance)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
                .task {
                    await model.start()
                }
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Window("Homeward", id: "homeward") {
            RootView(model: model)
        }
        .defaultSize(width: 760, height: 600)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            HomewardCommands()
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @AppStorage("showRemainingTime") private var showRemainingTime = false

    var body: some View {
        Group {
            if showRemainingTime, let transition = model.resolvedSchedule.nextTransition {
                Label(
                    transition.date.formatted(date: .omitted, time: .shortened),
                    systemImage: "house"
                )
            } else {
                Image(systemName: "house")
            }
        }
        .accessibilityLabel("Homeward")
        .accessibilityValue(accessibilityState)
    }

    private var accessibilityState: String {
        let state: String
        switch model.resolvedSchedule.phase {
        case .workAvailable:
            state = "Work available"
        case .windingDown:
            state = "Winding down"
        case .workClosed:
            state = model.closingRows.isEmpty ? "Work is closed" : "Closing work apps"
        case .temporarilyExtended:
            state = "Work extended"
        }
        if let transition = model.resolvedSchedule.nextTransition {
            return "\(state). Next transition \(transition.date.formatted(date: .abbreviated, time: .shortened))."
        }
        return state
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if requiresRecovery {
            Button("Open Recovery…") {
                openWindow(id: "homeward")
            }
            Divider()
            Button("Quit Homeward…") {
                confirmQuit()
            }
        } else if !model.isOnboardingComplete {
            Button("Finish Setup…") {
                openWindow(id: "homeward")
            }
            Divider()
            Button("Quit Homeward…") {
                confirmQuit()
            }
        } else {
            Section {
                Text(stateTitle)
                Text(transitionText)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("\(model.configuration.selectedApplications.count) work apps")
                Text(model.configuration.closeMode == .gentle ? "Gentle Close" : "Firm Close")
                if let activeOverride = model.resolvedSchedule.activeOverride {
                    Text(
                        "Today-only change until "
                            + activeOverride.expiresAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                    )
                }
            }

            if !model.closingRows.isEmpty {
                Button("Show Closing Details…") {
                    model.showClosingDetails()
                }
            }

            if model.resolvedSchedule.isAvailable {
                Button("End Work Now…") {
                    confirmEndWork()
                }
            } else {
                Button("Save a Thought…") {
                    model.showNoteCapture()
                }
            }

            Menu("Change Today Only…") {
                Button("Extend by 10 Minutes") {
                    Task { await model.createExtension(minutes: 10) }
                }
                Button("Extend by 15 Minutes") {
                    Task { await model.createExtension(minutes: 15) }
                }
                Button("Extend by 30 Minutes") {
                    Task { await model.createExtension(minutes: 30) }
                }
                Button("Choose Another Cutoff…") {
                    model.showCustomCutoff()
                }
                if !model.resolvedSchedule.isAvailable {
                    Button("Make Work Available Now") {
                        Task { await model.makeWorkAvailableNow() }
                    }
                }
                Button("Take Today Off…") {
                    confirmTakeTodayOff()
                }
                Divider()
                Button("Return to Weekly Schedule") {
                    Task { await model.returnToWeeklySchedule() }
                }
            }

            if model.forceEscalationPaused {
                Button("Resume Firm Closing…") {
                    confirmResumeFirmClosing()
                }
            }

            if model.loginItemStatus != .enabled || model.notificationStatus != .authorized {
                Divider()
                Button("Homeward Needs Attention…") {
                    openWindow(id: "homeward")
                }
            }

            Divider()
            Button("Open Homeward") {
                openWindow(id: "homeward")
            }
            Button("Settings…") {
                openWindow(id: "homeward")
            }
            Divider()
            Button("Quit Homeward…") {
                confirmQuit()
            }
        }
    }

    private var requiresRecovery: Bool {
        if case .configurationUnavailable = model.health {
            return true
        }
        return false
    }

    private var stateTitle: String {
        if !model.closingRows.isEmpty {
            return "Closing work apps"
        }
        switch model.resolvedSchedule.phase {
        case .workAvailable:
            return "Work available"
        case .windingDown:
            return "Winding down"
        case .workClosed:
            return "Work is closed"
        case .temporarilyExtended:
            return "Work extended"
        }
    }

    private var transitionText: String {
        guard let transition = model.resolvedSchedule.nextTransition else {
            return model.resolvedSchedule.isAvailable
                ? "Work apps are always available"
                : "No work window scheduled"
        }
        let formatted = transition.date.formatted(date: .abbreviated, time: .shortened)
        switch transition.cause {
        case .workWindowStarts:
            return "Available \(formatted)"
        case .workWindowEnds:
            return "Until \(formatted)"
        case .overrideExpires:
            return "Weekly schedule resumes \(formatted)"
        }
    }

    private func confirmEndWork() {
        let alert = NSAlert()
        alert.messageText = "End work now?"
        alert.informativeText = "Homeward will begin the configured closing flow for selected work apps."
        alert.addButton(withTitle: "End Work Now")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task { await model.endWorkNow() }
    }

    private func confirmResumeFirmClosing() {
        let alert = NSAlert()
        alert.messageText = "Resume Firm Closing?"
        alert.informativeText = "Homeward will ask selected apps to quit normally and begin a new 30-second grace period."
        alert.addButton(withTitle: "Resume Firm Closing")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task { await model.resumeFirmClosing() }
    }

    private func confirmTakeTodayOff() {
        let alert = NSAlert()
        alert.messageText = "Take today off?"
        alert.informativeText = "Homeward will apply the configured closing flow now and keep work apps unavailable through today."
        alert.addButton(withTitle: "Take Today Off")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task { await model.takeTodayOff() }
    }

    private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit Homeward?"
        alert.informativeText = "Pending force quits will be cancelled. Apps already asked to quit may still close. Selected apps will not be monitored until Homeward is reopened."
        alert.addButton(withTitle: "Quit Homeward")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        model.quit()
    }
}

private struct HomewardCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openWindow(id: "homeward")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
