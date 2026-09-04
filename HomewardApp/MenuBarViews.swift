import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: HomewardNavigationState
    let applicationDelegate: HomewardApplicationDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage(HomewardPreferenceKeys.showNextTransitionTime)
    private var showNextTransitionTime = false

    var body: some View {
        Group {
            if model.presentationSnapshot.state == .operational,
               showNextTransitionTime,
               let transition = model.resolvedSchedule.nextTransition {
                Label(
                    transition.date.formatted(date: .omitted, time: .shortened),
                    systemImage: "house"
                )
            } else {
                Image(systemName: "house")
            }
        }
        .accessibilityLabel("Homeward")
        .accessibilityValue(model.presentationSnapshot.accessibilityValue)
        .task {
            navigation.installMainWindowPresenter {
                NSApp.unhide(nil)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "homeward")
            }
            applicationDelegate.register(
                navigation: navigation,
                model: model
            )
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: HomewardNavigationState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        switch model.presentationSnapshot.state {
        case .starting:
            Text(model.presentationSnapshot.title)
            Divider()
            quitButton
        case .startupDelayed:
            Text(model.presentationSnapshot.title)
            if let detail = model.presentationSnapshot.transitionText {
                Text(detail)
            }
            Button("Retry") {
                model.retryStartup()
            }
            Divider()
            quitButton
        case .configurationRecovery, .applicationResolutionRecovery:
            Button("Open Recovery…") {
                navigation.requestMainWindow()
            }
            Divider()
            quitButton
        case .onboarding:
            Button("Finish Setup…") {
                navigation.requestMainWindow()
            }
            Divider()
            quitButton
        case .operational:
            operationalContent
        }
    }

    @ViewBuilder
    private var operationalContent: some View {
        Section {
            Text(model.presentationSnapshot.title)
            if let transitionText = model.presentationSnapshot.transitionText {
                Text(transitionText)
                    .foregroundStyle(.secondary)
            }
        }

        Section {
            Text("\(model.configuration.selectedApplications.count) work apps")
            Text(
                SchedulePresentation.closeModeName(
                    model.configuration.closeMode
                )
            )
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
            Button("Show Closing Progress…") {
                model.showClosingDetails()
            }
        }

        if model.presentationSnapshot.savedThoughtCount > 0 {
            Button(
                "Review Saved Thoughts (\(model.presentationSnapshot.savedThoughtCount))…"
            ) {
                navigation.requestMainWindow(.savedThoughts)
            }
        }

        if model.resolvedSchedule.isAvailable {
            Button("End Work Now…") {
                model.requestPolicyConfirmation(
                    .endWorkNow,
                    routeToToday: true
                )
            }
        } else {
            switch model.notesHealth {
            case .available:
                Button("Save a Thought…") {
                    model.showNoteCapture()
                }
            case .loading:
                Button("Loading Saved Thoughts…") {}
                    .disabled(true)
            case .unavailable:
                Button("Saved Thoughts Need Attention…") {
                    navigation.requestMainWindow(.savedThoughts)
                }
            }
        }

        Menu(TodayActionPresentation.menuTitle) {
            ForEach(model.todayActions, id: \.self) { action in
                if action == .returnToWeeklySchedule {
                    Divider()
                }
                Button(action.title) {
                    performTodayAction(action)
                }
            }
        }

        if model.forceEscalationPaused {
            Button("Resume Firm Closing…") {
                model.requestPolicyConfirmation(
                    .resumeFirmClosing,
                    routeToToday: true
                )
            }
        }

        if model.presentationSnapshot.attentionCount > 0 {
            Divider()
            Button(
                "Homeward Needs Attention (\(model.presentationSnapshot.attentionCount))…"
            ) {
                openPrimaryAttention()
            }
        }

        Divider()
        Button("Open Homeward") {
            navigation.requestMainWindow()
        }
        Button("Settings…") {
            openSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("About Homeward") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel()
        }
        Button("Hide Homeward") {
            if model.closingRows.contains(where: {
                $0.status == .countingDown
            }) {
                Task {
                    await model.stopForceQuit()
                    NSApp.hide(nil)
                }
            } else {
                NSApp.hide(nil)
            }
        }
        Divider()
        quitButton
    }

    private var quitButton: some View {
        Button("Quit Homeward…") {
            confirmQuit(model: model)
        }
    }

    private func performTodayAction(
        _ action: TodayActionPresentation.Action
    ) {
        switch action {
        case let .extend(minutes):
            Task { await model.createExtension(minutes: minutes) }
        case .chooseCutoff:
            model.showCustomCutoff()
        case .makeAvailable:
            Task { await model.makeWorkAvailableNow() }
        case .takeDayOff:
            confirmTakeTodayOff()
        case .returnToWeeklySchedule:
            Task { await model.returnToWeeklySchedule() }
        }
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openPrimaryAttention() {
        switch model.primaryAttentionDestination {
        case .workApps:
            navigation.requestMainWindow(.workApps)
        case .savedThoughts:
            navigation.requestMainWindow(.savedThoughts)
        case .settings, .none:
            openSettingsWindow()
        }
    }

    private func confirmTakeTodayOff() {
        let alert = NSAlert()
        alert.messageText =
            TodayActionPresentation.takeDayOffConfirmationTitle
        alert.informativeText =
            TodayActionPresentation.takeDayOffConfirmationMessage
        alert.addButton(
            withTitle:
                TodayActionPresentation.takeDayOffConfirmationActionTitle
        )
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        Task { await model.takeTodayOff() }
    }
}
