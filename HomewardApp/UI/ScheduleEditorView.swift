import HomewardCore
import SwiftUI

struct ScheduleEditorView: View {
    @ObservedObject var model: AppModel
    let requiresOnboardingConfirmation: Bool
    @State private var rules: [Weekday: DayRule]
    @State private var validationMessage: String?
    @State private var isSaving = false
    @State private var copySource: Weekday = .monday

    init(
        model: AppModel,
        requiresOnboardingConfirmation: Bool = false
    ) {
        self.model = model
        self.requiresOnboardingConfirmation = requiresOnboardingConfirmation
        _rules = State(initialValue: model.configuration.schedule.rules)
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
                            Text(weekdayName(weekday)).tag(weekday)
                        }
                    }
                    Menu("Copy to…") {
                        ForEach(
                            orderedWeekdays.filter { $0 != copySource },
                            id: \.self
                        ) { weekday in
                            Button(weekdayName(weekday)) {
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
            isSaving = true
            Task { @MainActor in
                await model.setSchedule(schedule)
                rules = model.configuration.schedule.rules
                validationMessage = model.lastError
                isSaving = false
            }
        } catch {
            validationMessage = scheduleValidationMessage(error)
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

    private func weekdayName(_ weekday: Weekday) -> String {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        return calendar.weekdaySymbols[weekday.rawValue - 1]
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

                if case .scheduled = rule {
                    DatePicker(
                        "From",
                        selection: timeBinding(isStart: true),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    Text("to")
                        .foregroundStyle(.secondary)
                    DatePicker(
                        "Until",
                        selection: timeBinding(isStart: false),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    Toggle("Next day", isOn: nextDayBinding)
                        .toggleStyle(.checkbox)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule.day.\(weekday.rawValue)")
    }

    private var weekdayName: String {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = Locale.autoupdatingCurrent
        return calendar.weekdaySymbols[weekday.rawValue - 1]
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
                    guard let start = try? LocalTime(hour: 9, minute: 0),
                          let end = try? LocalTime(hour: 17, minute: 0) else {
                        return
                    }
                    rule = .scheduled(
                        start: start,
                        end: end,
                        endsNextDay: false
                    )
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
