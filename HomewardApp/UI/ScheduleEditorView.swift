import HomewardCore
import SwiftUI

struct ScheduleEditorView: View {
    @ObservedObject var model: AppModel
    let requiresOnboardingConfirmation: Bool
    @State private var rules: [Weekday: DayRule]
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var copySource: Weekday = .monday
    @State private var pendingSchedule: WeeklySchedule?
    @State private var showImmediateCloseConfirmation = false
    @State private var lastSavedScheduleWasConfirmed: Bool

    init(
        model: AppModel,
        requiresOnboardingConfirmation: Bool = false
    ) {
        self.model = model
        self.requiresOnboardingConfirmation = requiresOnboardingConfirmation
        _rules = State(initialValue: model.configuration.schedule.rules)
        _lastSavedScheduleWasConfirmed = State(
            initialValue: model.configuration.onboardingScheduleConfirmed
        )
    }

    var body: some View {
        Form {
            Section {
                Text("Choose when work apps are available. Homeward follows this Mac’s current time zone.")
                    .foregroundStyle(.secondary)
            }

            Section("Weekly schedule") {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    DayRuleRow(
                        weekday: weekday,
                        rule: ruleBinding(for: weekday)
                    )
                }
            }

            Section("Copy hours") {
                HStack {
                    Picker("Source day", selection: $copySource) {
                        ForEach(orderedWeekdays, id: \.self) { weekday in
                            Text(weekdayDisplayName(weekday)).tag(weekday)
                        }
                    }
                    Menu("Copy to…") {
                        ForEach(
                            orderedWeekdays.filter { $0 != copySource },
                            id: \.self
                        ) { weekday in
                            Button(weekdayDisplayName(weekday)) {
                                if let sourceRule = rules[copySource] {
                                    rules[weekday] = sourceRule
                                    if requiresOnboardingConfirmation {
                                        model.markOnboardingScheduleDirty()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("schedule.validation")
                }
            }

            HStack {
                Spacer()
                Button("Reset Draft") {
                    rules = model.configuration.schedule.rules
                    validationMessage = nil
                    if requiresOnboardingConfirmation,
                       lastSavedScheduleWasConfirmed {
                        model.restoreOnboardingScheduleConfirmation()
                    }
                }
                Button("Save Schedule") {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(isSaving)
                .accessibilityIdentifier("schedule.save")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Schedule")
        .confirmationDialog(
            "Save and close work apps now?",
            isPresented: $showImmediateCloseConfirmation
        ) {
            Button("Save & Close", role: .destructive) {
                if let pendingSchedule {
                    performSave(pendingSchedule)
                }
                pendingSchedule = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSchedule = nil
            }
        } message: {
            Text("This schedule makes the current time blocked. Homeward will begin the configured closing flow.")
        }
        .accessibilityIdentifier("schedule.view")
    }

    private var orderedWeekdays: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    private func ruleBinding(for weekday: Weekday) -> Binding<DayRule> {
        Binding(
            get: { rules[weekday] ?? .blockedAllDay },
            set: {
                rules[weekday] = $0
                validationMessage = nil
                if requiresOnboardingConfirmation {
                    model.markOnboardingScheduleDirty()
                }
            }
        )
    }

    private func save() {
        do {
            let schedule = try WeeklySchedule(rules: rules)
            let result = ScheduleResolver().resolve(
                schedule: schedule,
                overrides: model.configuration.overrides,
                at: Date(),
                calendar: .autoupdatingCurrent,
                warnings: model.configuration.warningPreferences
            )
            if model.configuration.completedOnboarding,
               model.resolvedSchedule.isAvailable,
               !result.isAvailable {
                pendingSchedule = schedule
                showImmediateCloseConfirmation = true
            } else {
                performSave(schedule)
            }
        } catch {
            validationMessage = scheduleValidationMessage(error)
        }
    }

    private func performSave(_ schedule: WeeklySchedule) {
        isSaving = true
        model.clearError()
        Task { @MainActor in
            await model.setSchedule(schedule)
            rules = model.configuration.schedule.rules
            validationMessage = model.lastError
            lastSavedScheduleWasConfirmed =
                model.configuration.onboardingScheduleConfirmed
            isSaving = false
        }
    }

    private func scheduleValidationMessage(_ error: Error) -> String {
        switch error {
        case ValidationError.equalScheduleBoundaries:
            "Start and end times must be different."
        case ValidationError.sameDayWindowEndsBeforeStart:
            "A same-day window must end after it starts."
        case ValidationError.invalidOvernightWindow:
            "An overnight window must end earlier on the next day."
        case ValidationError.overnightConflictsWithBlockedDay:
            "An overnight window cannot continue into a day marked Blocked all day."
        default:
            "Review the schedule and try again."
        }
    }

}

private struct DayRuleRow: View {
    enum Mode: String, CaseIterable, Identifiable {
        case scheduled = "Scheduled hours"
        case availableAllDay = "Available all day"
        case blockedAllDay = "Blocked all day"

        var id: String { rawValue }
    }

    let weekday: Weekday
    @Binding var rule: DayRule

    var body: some View {
        LabeledContent(weekdayName) {
            HStack {
                Picker("Mode", selection: modeBinding) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityLabel("\(weekdayName) mode")

                if case .scheduled = rule {
                    DatePicker(
                        "From",
                        selection: timeBinding(isStart: true),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .accessibilityLabel("\(weekdayName) start time")
                    Text("to")
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "Until",
                        selection: timeBinding(isStart: false),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .accessibilityLabel("\(weekdayName) end time")
                    Toggle("Next day", isOn: nextDayBinding)
                        .toggleStyle(.checkbox)
                        .accessibilityLabel("\(weekdayName) ends next day")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule.day.\(weekday.rawValue)")
    }

    private var weekdayName: String {
        weekdayDisplayName(weekday)
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: {
                switch rule {
                case .scheduled:
                    .scheduled
                case .availableAllDay:
                    .availableAllDay
                case .blockedAllDay:
                    .blockedAllDay
                }
            },
            set: { mode in
                switch mode {
                case .scheduled:
                    guard let defaultRule = try? WeeklySchedule
                        .defaultWorkdayRule() else {
                        return
                    }
                    rule = defaultRule
                case .availableAllDay:
                    rule = .availableAllDay
                case .blockedAllDay:
                    rule = .blockedAllDay
                }
            }
        )
    }

    private func timeBinding(isStart: Bool) -> Binding<Date> {
        Binding(
            get: {
                guard case let .scheduled(start, end, _) = rule else {
                    return referenceDate(hour: 9, minute: 0)
                }
                let time = isStart ? start : end
                return referenceDate(hour: time.hour, minute: time.minute)
            },
            set: { date in
                guard case let .scheduled(start, end, endsNextDay) = rule else {
                    return
                }
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                guard let time = try? LocalTime(
                    hour: components.hour ?? 0,
                    minute: components.minute ?? 0
                ) else {
                    return
                }
                rule = .scheduled(
                    start: isStart ? time : start,
                    end: isStart ? end : time,
                    endsNextDay: endsNextDay
                )
            }
        )
    }

    private var nextDayBinding: Binding<Bool> {
        Binding(
            get: {
                guard case let .scheduled(_, _, endsNextDay) = rule else {
                    return false
                }
                return endsNextDay
            },
            set: { value in
                guard case let .scheduled(start, end, _) = rule else {
                    return
                }
                rule = .scheduled(start: start, end: end, endsNextDay: value)
            }
        )
    }

    private func referenceDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        )!
    }
}

private func weekdayDisplayName(_ weekday: Weekday) -> String {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale.autoupdatingCurrent
    return calendar.weekdaySymbols[weekday.rawValue - 1]
}
