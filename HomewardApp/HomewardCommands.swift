import AppKit
import SwiftUI

struct HomewardCommands: Commands {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(!model.isPolicyMutationEnabled)
        }

        CommandGroup(replacing: .appTermination) {
            Button("Quit Homeward…") {
                confirmQuit(model: model)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

@MainActor
func confirmQuit(model: AppModel) {
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
