import AppKit
import HomewardCore
import SwiftUI
import UniformTypeIdentifiers

struct AppPickerView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var pendingSelection: SelectedApplication?
    @State private var showImmediateCloseConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
            }
            HStack {
                TextField("Search applications", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("apps.search")
                Button("Choose Application…") {
                    chooseApplication()
                }
                .accessibilityIdentifier("apps.choose")
            }

            if model.isCatalogLoading {
                ProgressView("Looking for applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredCatalog.isEmpty {
                ContentUnavailableView {
                    Label(
                        searchText.isEmpty ? "No applications found" : "No matching applications",
                        systemImage: "square.grid.2x2"
                    )
                } description: {
                    Text("Choose an application directly if it is not listed.")
                } actions: {
                    Button("Choose Application…") {
                        chooseApplication()
                    }
                }
            } else {
                List(filteredCatalog) { application in
                    applicationRow(application)
                }
                .listStyle(.inset)
            }

            selectedApplications

            if browserIsSelected {
                Label(
                    "Homeward manages the whole browser, including every profile and window. Use a separate browser for personal browsing.",
                    systemImage: "globe"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Work Apps")
        .dropDestination(for: URL.self) { urls, _ in
            let applicationURLs = urls.filter {
                $0.pathExtension.lowercased() == "app"
            }
            guard !requiresImmediateCloseConfirmation || confirmImmediateClose() else {
                return false
            }
            Task {
                for url in applicationURLs {
                    await model.addApplication(at: url)
                }
            }
            return !applicationURLs.isEmpty
        }
        .accessibilityIdentifier("apps.view")
        .confirmationDialog(
            "Add and close this work app now?",
            isPresented: $showImmediateCloseConfirmation
        ) {
            Button("Add & Close", role: .destructive) {
                if let pendingSelection {
                    Task { await model.addApplication(pendingSelection) }
                }
                pendingSelection = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSelection = nil
            }
        } message: {
            Text("The current time is blocked. Homeward will immediately apply the configured closing flow.")
        }
        .task {
            await model.refreshCatalog()
        }
    }

    private var filteredCatalog: [CatalogApplication] {
        guard !searchText.isEmpty else {
            return model.catalog
        }
        return model.catalog.filter {
            $0.selection.displayName.localizedCaseInsensitiveContains(searchText)
                || ($0.selection.developerName?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var browserIsSelected: Bool {
        model.configuration.selectedApplications.contains { application in
            application.bundleIdentifier.map(
                ApplicationCatalog.browserBundleIdentifiers.contains
            ) ?? false
        }
    }

    @ViewBuilder
    private func applicationRow(_ application: CatalogApplication) -> some View {
        let isSelected = model.configuration.selectedApplications.contains {
            $0.stableSelectionKey == application.selection.stableSelectionKey
        }
        HStack(spacing: 12) {
            Image(nsImage: application.icon)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(application.selection.displayName)
                if let developer = application.selection.developerName,
                   !developer.isEmpty {
                    Text(developer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle(
                application.selection.displayName,
                isOn: Binding(
                    get: { isSelected },
                    set: { selected in
                        Task {
                            if selected {
                                if requiresImmediateCloseConfirmation {
                                    pendingSelection = application.selection
                                    showImmediateCloseConfirmation = true
                                } else {
                                    await model.addApplication(application.selection)
                                }
                            } else if let existing = model.configuration.selectedApplications.first(
                                where: {
                                    $0.stableSelectionKey
                                        == application.selection.stableSelectionKey
                                }
                            ) {
                                await model.removeApplication(id: existing.id)
                            }
                        }
                    }
                )
            )
            .labelsHidden()
            .accessibilityLabel(application.selection.displayName)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("apps.row.\(application.id)")
    }

    private var selectedApplications: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected (\(model.configuration.selectedApplications.count))")
                .font(.headline)
            if model.configuration.selectedApplications.isEmpty {
                Text("Choose at least one work app.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.configuration.selectedApplications) { application in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(application.displayName)
                            if !application.isResolvable {
                                Text("Needs reselection")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if !application.isResolvable {
                            Button("Reselect…") {
                                chooseReplacement(for: application.id)
                            }
                        }
                        Button("Remove") {
                            Task { await model.removeApplication(id: application.id) }
                        }
                        .accessibilityLabel("Remove \(application.displayName)")
                    }
                }
            }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Work Application"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK,
              !panel.urls.isEmpty,
              !requiresImmediateCloseConfirmation || confirmImmediateClose()
        else {
            return
        }
        Task {
            for url in panel.urls {
                await model.addApplication(at: url)
            }
        }
    }

    private var requiresImmediateCloseConfirmation: Bool {
        model.configuration.completedOnboarding
            && !model.resolvedSchedule.isAvailable
    }

    private func confirmImmediateClose() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Add and close selected work apps now?"
        alert.informativeText = "The current time is blocked. Homeward will immediately apply the configured closing flow."
        alert.addButton(withTitle: "Add & Close")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func chooseReplacement(for id: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Reselect Work Application"
        panel.prompt = "Reselect"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        Task { await model.replaceApplication(id: id, with: url) }
    }
}
