import AppKit
import HomewardCore
import SwiftUI
import UniformTypeIdentifiers

struct AppPickerView: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var pendingSelection: SelectedApplication?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                Label("Choose the apps that end with work", systemImage: "square.grid.2x2")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Homeward only manages apps you select. You can change this list at any time."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .top], HomewardSpacing.xLarge)
            .padding(.bottom, 18)
            .accessibilityElement(children: .combine)

            if let error = model.lastError {
                InlineErrorView(message: error) {
                    model.clearError()
                }
                .padding(.horizontal, HomewardSpacing.xLarge)
                .padding(.bottom, 12)
            }

            selectedApplications
                .padding(.horizontal, HomewardSpacing.xLarge)
                .padding(.bottom, 18)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        catalogHeading
                        Spacer()
                        Button("Choose Application…") {
                            chooseApplication()
                        }
                        .accessibilityIdentifier("apps.choose")
                    }
                    VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                        catalogHeading
                        Button("Choose Application…") {
                            chooseApplication()
                        }
                        .accessibilityIdentifier("apps.choose")
                    }
                }

                TextField("Search applications", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search available applications")
                    .accessibilityIdentifier("apps.search")

                catalogContent

                Label(
                    "You can also drop application files here.",
                    systemImage: "arrow.down.app"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
            .padding(HomewardSpacing.xLarge)
        }
        .navigationTitle("Work Apps")
        .dropDestination(for: URL.self) { urls, _ in
            let applicationURLs = urls.filter {
                $0.pathExtension.lowercased() == "app"
            }
            guard !applicationURLs.isEmpty else {
                return false
            }
            guard !requiresImmediateCloseConfirmation || confirmImmediateClose() else {
                return false
            }
            Task {
                for url in applicationURLs {
                    await model.addApplication(at: url)
                }
            }
            return true
        }
        .accessibilityIdentifier("apps.view")
        .confirmationDialog(
            "Add and close this work app now?",
            isPresented: pendingSelectionConfirmation
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

    private var catalogHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Available applications")
                .font(.headline)
            Text("Selected apps also remain visible here for quick changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if model.isCatalogLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Looking for applications on this Mac…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .accessibilityElement(children: .combine)
        } else if filteredCatalog.isEmpty {
            ContentUnavailableView {
                Label(
                    searchText.isEmpty ? "No applications found" : "No matches",
                    systemImage: searchText.isEmpty
                        ? "square.grid.2x2"
                        : "magnifyingglass"
                )
            } description: {
                Text(
                    searchText.isEmpty
                        ? "Choose an application directly or drop its app file here."
                        : "Try another search or choose the application directly."
                )
            } actions: {
                Button("Choose Application…") {
                    chooseApplication()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            List(filteredCatalog) { application in
                applicationRow(application)
            }
            .listStyle(.inset)
            .frame(minHeight: 120, maxHeight: .infinity)
        }
    }

    private var filteredCatalog: [CatalogApplication] {
        let matches: [CatalogApplication]
        if searchText.isEmpty {
            matches = model.catalog
        } else {
            matches = model.catalog.filter {
                $0.selection.displayName.localizedCaseInsensitiveContains(searchText)
                    || ($0.selection.developerName?
                        .localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return matches.sorted { lhs, rhs in
            let lhsSelected = isSelected(lhs.selection)
            let rhsSelected = isSelected(rhs.selection)
            if lhsSelected != rhsSelected {
                return lhsSelected
            }
            return lhs.selection.displayName.localizedStandardCompare(
                rhs.selection.displayName
            ) == .orderedAscending
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
        let isSelected = isSelected(application.selection)
        HStack(spacing: 12) {
            Image(nsImage: application.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(application.selection.displayName)
                    .fontWeight(isSelected ? .semibold : .regular)
                if let developer = application.selection.developerName,
                   !developer.isEmpty {
                    Text(developer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isSelected {
                Text("Selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle(
                application.selection.displayName,
                isOn: Binding(
                    get: { isSelected },
                    set: { selected in
                        Task {
                            if selected {
                                if requiresImmediateCloseConfirmation {
                                    pendingSelection = application.selection
                                } else {
                                    await model.addApplication(application.selection)
                                }
                            } else if let existing = selectedApplication(
                                matching: application.selection
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Selected work apps")
                    .font(.headline)
                Text("\(model.configuration.selectedApplications.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                HomewardStatusLabel(
                    title: model.configuration.selectedApplications.isEmpty
                        ? "Required"
                        : "Ready",
                    symbol: model.configuration.selectedApplications.isEmpty
                        ? "circle.dashed"
                        : "checkmark.circle.fill",
                    tone: model.configuration.selectedApplications.isEmpty
                        ? .attention
                        : .ready
                )
            }
            if model.configuration.selectedApplications.isEmpty {
                HomewardCard {
                    HStack(spacing: HomewardSpacing.medium) {
                        Image(systemName: "app.dashed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 40, height: 40)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Choose at least one work app")
                                .font(.headline)
                            Text("Your personal apps remain outside Homeward’s control.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(model.configuration.selectedApplications) { application in
                            selectedApplicationCard(application)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.automatic)
            }

            if browserIsSelected {
                Label(
                    "A selected browser means every profile and window. "
                        + "Use a separate browser for personal browsing.",
                    systemImage: "globe"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectedApplicationCard(
        _ application: SelectedApplication
    ) -> some View {
        HomewardCard(padding: HomewardSpacing.medium) {
            HStack(spacing: HomewardSpacing.medium) {
                Image(nsImage: icon(for: application))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(application.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    Text(application.isResolvable ? "Ready" : "Needs reselection")
                        .font(.caption)
                        .foregroundStyle(
                            application.isResolvable
                                ? Color.secondary
                                : HomewardTone.attention.color
                        )
                }

                Spacer(minLength: HomewardSpacing.xSmall)

                Menu {
                    if !application.isResolvable {
                        Button("Reselect…") {
                            chooseReplacement(for: application.id)
                        }
                    }
                    Button("Remove", role: .destructive) {
                        Task { await model.removeApplication(id: application.id) }
                    }
                    .accessibilityLabel("Remove \(application.displayName)")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Actions for \(application.displayName)")
            }
        }
        .frame(width: 260, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func icon(for application: SelectedApplication) -> NSImage {
        if let catalogApplication = model.catalog.first(where: {
            selectionsMatch($0.selection, application)
        }) {
            return catalogApplication.icon
        }
        return NSWorkspace.shared.icon(forFile: application.bundlePath)
    }

    private func isSelected(_ application: SelectedApplication) -> Bool {
        selectedApplication(matching: application) != nil
    }

    private func selectedApplication(
        matching application: SelectedApplication
    ) -> SelectedApplication? {
        model.configuration.selectedApplications.first {
            selectionsMatch($0, application)
        }
    }

    private func selectionsMatch(
        _ lhs: SelectedApplication,
        _ rhs: SelectedApplication
    ) -> Bool {
        lhs.stableSelectionKey == rhs.stableSelectionKey
    }

    private func chooseApplication() {
        let panel = applicationPanel(
            title: "Choose a Work Application",
            prompt: "Choose",
            allowsMultipleSelection: true
        )
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
        let panel = applicationPanel(
            title: "Reselect Work Application",
            prompt: "Reselect",
            allowsMultipleSelection: false
        )
        guard panel.runModal() == .OK,
              let url = panel.url,
              !requiresImmediateCloseConfirmation || confirmImmediateClose()
        else {
            return
        }
        Task { await model.replaceApplication(id: id, with: url) }
    }

    private var pendingSelectionConfirmation: Binding<Bool> {
        Binding(
            get: { pendingSelection != nil },
            set: { if !$0 { pendingSelection = nil } }
        )
    }

    private func applicationPanel(
        title: String,
        prompt: String,
        allowsMultipleSelection: Bool
    ) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = prompt
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = [.applicationBundle]
        return panel
    }
}
