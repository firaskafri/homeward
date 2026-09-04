import HomewardCore

enum SchedulePresentation {
    static func stateTitle(
        schedule: ResolvedSchedule,
        closingCount: Int
    ) -> String {
        if closingCount > 0 {
            return "Closing work apps"
        }
        switch schedule.phase {
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
