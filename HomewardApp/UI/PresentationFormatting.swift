import HomewardCore

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
                badgeTitle: "Protected",
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

    static func stateTitle(
        schedule: ResolvedSchedule,
        closingCount: Int
    ) -> String {
        status(schedule: schedule, closingCount: closingCount).title
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
