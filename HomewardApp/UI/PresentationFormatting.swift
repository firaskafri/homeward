import HomewardCore

struct HomewardPresentationSnapshot: Equatable {
    enum State: Equatable {
        case starting
        case startupDelayed
        case configurationRecovery
        case applicationResolutionRecovery
        case onboarding
        case operational
    }

    let state: State
    let title: String
    let transitionText: String?
    let savedThoughtCount: Int
    let attentionCount: Int

    var accessibilityValue: String {
        [title, transitionText]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    static func resolve(
        health: AppModel.Health,
        onboardingComplete: Bool,
        schedule: ResolvedSchedule,
        closingCount: Int,
        forceEscalationPaused: Bool,
        savedThoughtCount: Int,
        attentionCount: Int
    ) -> Self {
        switch health {
        case .starting:
            return Self(
                state: .starting,
                title: "Starting Homeward…",
                transitionText: nil,
                savedThoughtCount: 0,
                attentionCount: attentionCount
            )
        case .startupDelayed:
            return Self(
                state: .startupDelayed,
                title: "Starting Homeward…",
                transitionText:
                    "This is taking longer than expected. App closing has not started.",
                savedThoughtCount: 0,
                attentionCount: attentionCount
            )
        case .configurationUnavailable:
            return Self(
                state: .configurationRecovery,
                title: "App closing is paused",
                transitionText:
                    "Homeward could not verify its saved settings, so it will not close any applications.",
                savedThoughtCount: 0,
                attentionCount: attentionCount
            )
        case .applicationResolutionUnavailable:
            return Self(
                state: .applicationResolutionRecovery,
                title: "App closing has not started",
                transitionText:
                    "Homeward could not verify the selected applications. Your saved settings were kept.",
                savedThoughtCount: 0,
                attentionCount: attentionCount
            )
        case .ready:
            break
        }
        guard onboardingComplete else {
            return Self(
                state: .onboarding,
                title: "Finish setting up Homeward",
                transitionText: nil,
                savedThoughtCount: 0,
                attentionCount: attentionCount
            )
        }
        if forceEscalationPaused {
            return Self(
                state: .operational,
                title: "Force quit is paused",
                transitionText:
                    "Work apps are still unavailable. Resume starts a new "
                    + "\(HomewardPolicy.firmGracePeriodDescription) grace period.",
                savedThoughtCount: savedThoughtCount,
                attentionCount: attentionCount
            )
        }
        let status = SchedulePresentation.status(
            schedule: schedule,
            closingCount: closingCount
        )
        return Self(
            state: .operational,
            title: status.title,
            transitionText: SchedulePresentation.transitionText(for: schedule),
            savedThoughtCount: savedThoughtCount,
            attentionCount: attentionCount
        )
    }
}

enum TodayActionPresentation {
    enum Action: Hashable {
        case extend(minutes: Int)
        case chooseCutoff
        case makeAvailable
        case takeDayOff
        case returnToWeeklySchedule

        var title: String {
            switch self {
            case let .extend(minutes):
                "Extend by \(minutes) Minutes"
            case .chooseCutoff:
                "Choose Another Cutoff…"
            case .makeAvailable:
                "Make Work Available Now"
            case .takeDayOff:
                "Take Today Off…"
            case .returnToWeeklySchedule:
                "Return to Weekly Schedule"
            }
        }
    }

    static let menuTitle = "Change Today Only…"
    static let contextDescription = "Your weekly schedule will not change."
    static let takeDayOffConfirmationTitle = "Take today off?"
    static let takeDayOffConfirmationActionTitle = "Take Today Off"
    static let takeDayOffConfirmationMessage =
        "Homeward will apply the configured closing flow now and keep "
        + "work apps unavailable through today."

    static func actions(
        canExtendToday: Bool,
        isAvailable: Bool,
        hasAvailabilityOverride: Bool
    ) -> [Action] {
        var actions: [Action] = []
        if canExtendToday {
            actions += HomewardPolicy.extensionDurationsMinutes.map {
                .extend(minutes: $0)
            }
        }
        actions.append(.chooseCutoff)
        if !isAvailable {
            actions.append(.makeAvailable)
        }
        actions.append(.takeDayOff)
        if hasAvailabilityOverride {
            actions.append(.returnToWeeklySchedule)
        }
        return actions
    }
}

struct ScheduleStatusPresentation {
    let title: String
    let badgeTitle: String
    let symbol: String
    let tone: HomewardTone
}

struct ReadinessPresentation {
    let status: String
    let detail: String
    let symbol: String
    let tone: HomewardTone

    static func login(
        _ status: LoginItemService.Status,
        readyTitle: String,
        unhealthySymbol: String = "exclamationmark.circle.fill"
    ) -> Self {
        switch status {
        case .enabled:
            Self(
                status: readyTitle,
                detail: "Homeward starts automatically when you log in.",
                symbol: "checkmark.circle.fill",
                tone: .ready
            )
        case .notRegistered:
            Self(
                status: "Off",
                detail: "Homeward works only while it is open.",
                symbol: unhealthySymbol,
                tone: .attention
            )
        case .requiresApproval:
            Self(
                status: "Approval required",
                detail: "Allow Homeward in Login Items.",
                symbol: unhealthySymbol,
                tone: .attention
            )
        case .notFound:
            Self(
                status: "Unavailable",
                detail: "Start at Login could not be found.",
                symbol: unhealthySymbol,
                tone: .attention
            )
        case .unavailable:
            Self(
                status: "Unavailable",
                detail: "Start at Login cannot be checked right now.",
                symbol: unhealthySymbol,
                tone: .attention
            )
        }
    }

    static func notifications(
        _ status: HomewardNotificationService.AuthorizationStatus,
        readyTitle: String,
        unhealthySymbol: String = "exclamationmark.circle.fill",
        unhealthyTone: HomewardTone = .attention
    ) -> Self {
        switch status {
        case .authorized:
            Self(
                status: readyTitle,
                detail: "Wind-down notices are enabled.",
                symbol: "checkmark.circle.fill",
                tone: .ready
            )
        case .notDetermined:
            Self(
                status: "Not requested",
                detail: "Wind-down notifications are off.",
                symbol: unhealthySymbol,
                tone: unhealthyTone
            )
        case .denied:
            Self(
                status: "Off",
                detail: "App closing still works without notifications.",
                symbol: unhealthySymbol,
                tone: unhealthyTone
            )
        case .unavailable:
            Self(
                status: "Unavailable",
                detail: "Notifications cannot be checked right now.",
                symbol: unhealthySymbol,
                tone: unhealthyTone
            )
        }
    }
}

enum SchedulePresentation {
    static func status(
        schedule: ResolvedSchedule,
        closingCount: Int
    ) -> ScheduleStatusPresentation {
        if closingCount > 0 {
            return ScheduleStatusPresentation(
                title: "Closing work apps",
                badgeTitle: "Closing",
                symbol: "power",
                tone: .attention
            )
        }
        return switch schedule.phase {
        case .workAvailable:
            ScheduleStatusPresentation(
                title: "Work available",
                badgeTitle: "Available",
                symbol: "checkmark.circle.fill",
                tone: .ready
            )
        case .windingDown:
            ScheduleStatusPresentation(
                title: "Winding down",
                badgeTitle: "Ending soon",
                symbol: "clock.fill",
                tone: .attention
            )
        case .workClosed:
            ScheduleStatusPresentation(
                title: "Work is closed",
                badgeTitle: "Closed",
                symbol: "moon.stars.fill",
                tone: .rest
            )
        case .temporarilyExtended:
            ScheduleStatusPresentation(
                title: "Work extended",
                badgeTitle: "Extended",
                symbol: "clock.badge.plus",
                tone: .attention
            )
        }
    }

    static func transitionText(for schedule: ResolvedSchedule) -> String {
        guard let transition = schedule.nextTransition else {
            return schedule.isAvailable
                ? "Work apps are always available"
                : "No work window scheduled"
        }
        let formatted = transition.date.formatted(
            date: .abbreviated,
            time: .shortened
        )
        switch transition.cause {
        case .workWindowStarts:
            return "Available \(formatted)"
        case .workWindowEnds:
            return "Until \(formatted)"
        case .overrideExpires:
            return "Weekly schedule resumes \(formatted)"
        }
    }

    static func closeModeName(_ mode: CloseMode) -> String {
        mode == .gentle ? "Gentle Close" : "Firm Close"
    }

    static func overrideName(_ kind: OverrideKind) -> String {
        switch kind {
        case .endWorkNow:
            "Work ended early"
        case .fixedExtension:
            "Extended"
        case .customCutoff:
            "Custom cutoff"
        case .makeAvailable:
            "Work available"
        case .takeDayOff:
            "Day off"
        case .forceEscalationPaused:
            "Force quit paused"
        }
    }
}
