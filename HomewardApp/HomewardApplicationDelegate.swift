import AppKit

@MainActor
final class HomewardApplicationDelegate: NSObject, NSApplicationDelegate {
    private static let delayedStartupThreshold: Duration = .seconds(3)

    private weak var navigation: HomewardNavigationState?
    private weak var model: AppModel?
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapRevision = 0
    private var didFinishLaunching = false
    private var pendingReopenRoute: HomewardRoute?
    private var terminationInProgress = false

    func register(
        navigation: HomewardNavigationState,
        model: AppModel
    ) {
        self.navigation = navigation
        self.model = model
        model.installBootstrapRetryHandler { [weak self] in
            self?.restartBootstrap()
        }
        if let pendingReopenRoute {
            self.pendingReopenRoute = nil
            navigation.requestMainWindow(pendingReopenRoute)
        }
        if didFinishLaunching {
            beginBootstrap()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        didFinishLaunching = true
        beginBootstrap()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let model, model.isPolicyMutationEnabled else {
            return
        }
        Task {
            await model.refreshSystemStatuses()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if let navigation {
            navigation.requestMainWindow(.today)
        } else {
            pendingReopenRoute = .today
        }
        return true
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        guard let model else {
            return .terminateNow
        }
        guard !terminationInProgress else {
            return .terminateLater
        }
        terminationInProgress = true
        Task {
            await model.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func beginBootstrap() {
        guard bootstrapTask == nil, let model else {
            return
        }
        bootstrapRevision &+= 1
        let revision = bootstrapRevision
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let delayedTask = Task { @MainActor [weak self] in
                try? await Task.sleep(
                    for: Self.delayedStartupThreshold
                )
                guard !Task.isCancelled,
                      let self,
                      self.bootstrapRevision == revision else {
                    return
                }
                self.model?.markStartupDelayed()
            }
            await model.start()
            delayedTask.cancel()
            guard !Task.isCancelled,
                  bootstrapRevision == revision else {
                return
            }
            bootstrapTask = nil
            if model.presentationSnapshot.state != .operational {
                navigation?.requestMainWindow()
            }
        }
    }

    private func restartBootstrap() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        beginBootstrap()
    }
}
