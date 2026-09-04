import HomewardCore
import SwiftUI

struct ScheduleEditorView: View {
    @ObservedObject var model: AppModel
    let requiresOnboardingConfirmation: Bool
    @State private var rules: [Weekday: DayRule]
    @State private var validationMessage: String?
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @State private var copySource: Weekday = .monday
    @State private var pendingSchedule: WeeklySchedule?
    @State private var lastSavedScheduleWasConfirmed: Bool
    @State private var draftRevision: Int
    @State private var draftEditRevision = 0
    @State private var showsCopyTools = false

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
        _draftRevision = State(initialValue: model.policyRevision)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                    Label("Set your work window", systemImage: "calendar.badge.clock")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "Selected work apps stay available during these hours and "
                            + "close outside them. Times follow this Mac’s current time zone."
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, HomewardSpacing.xSmall)
                .accessibilityElement(children: .combine)
            }

            Section("This week") {
                Text(weeklySummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Weekly schedule: \(weeklySummary)")
            }

            Section {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    DayRuleRow(
                        weekday: weekday,
                        rule: ruleBinding(for: weekday)
                    )
                }
            } header: {
                Text("Daily availability")
            } footer: {
                Text("Overnight hours belong to the day on which they begin.")
            }

            Section {
                DisclosureGroup(
                    "Copy hours to another day",
                    isExpanded: $showsCopyTools
                ) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            copySourcePicker
                            Spacer()
                            copyDestinationMenu
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            copySourcePicker
                            copyDestinationMenu
                        }
                    }
                    .padding(.top, HomewardSpacing.small)
                }
            }

            if requiresOnboardingConfirmation {
                Section {
                    HomewardStatusLabel(
                        title: model.configuration.onboardingScheduleConfirmed
                            ? "Schedule confirmed"
                            : "Save this schedule to continue",
                        symbol: model.configuration.onboardingScheduleConfirmed
                            ? "checkmark.circle.fill"
                            : "circle.dashed",
                        tone: model.configuration.onboardingScheduleConfirmed
                            ? .ready
                            : .attention
                    )
                    .accessibilityElement(children: .combine)
                }
            }

            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("schedule.validation")
                }
            }

            if let saveErrorMessage {
                Section {
                    InlineErrorView(message: saveErrorMessage) {
                        self.saveErrorMessage = nil
                        model.clearError()
                    }
                }
            }

            Section {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        saveStatus
                        Spacer()
                        scheduleActions
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        saveStatus
                        scheduleActions
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Schedule")
        .confirmationDialog(
            "Save and close work apps now?",
            isPresented: pendingScheduleConfirmation
        ) {
            Button("Save & Close", role: .destructive) {
                if let pendingSchedule {
                    performSave(
                        pendingSchedule,
                        confirmsImmediateClose: true
                    )
                }
                pendingSchedule = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSchedule = nil
            }
        } message: {
            Text(
                "This change makes the current time unavailable. Homeward will begin "
                    + "\(SchedulePresentation.closeModeName(model.configuration.closeMode)) "
                    + "after the change is saved."
            )
        }
        .accessibilityIdentifier("schedule.view")
    }

    private var copySourcePicker: some View {
        Picker("Copy from", selection: $copySource) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                Text(weekdayDisplayName(weekday)).tag(weekday)
            }
        }
        .fixedSize()
    }

    private var copyDestinationMenu: some View {
        Menu("Copy to…") {
            ForEach(
                orderedWeekdays.filter { $0 != copySource },
                id: \.self
            ) { weekday in
                Button(weekdayDisplayName(weekday)) {
                    if let sourceRule = rules[copySource] {
                        rules[weekday] = sourceRule
                        draftEditRevision &+= 1
                        validationMessage = nil
                        if requiresOnboardingConfirmation {
                            model.markOnboardingScheduleDirty()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        if rules == model.configuration.schedule.rules {
            HomewardStatusLabel(
                title: "Saved",
                symbol: "checkmark.circle",
                tone: .neutral
            )
        } else {
            HomewardStatusLabel(
                title: "Unsaved changes",
                symbol: "circle.fill",
                tone: .attention
            )
        }
    }

    private var scheduleActions: some View {
        HStack {
            Button("Reset Draft") {
                rules = model.configuration.schedule.rules
                draftRevision = model.policyRevision
                draftEditRevision &+= 1
                validationMessage = nil
                saveErrorMessage = nil
                if requiresOnboardingConfirmation,
                   lastSavedScheduleWasConfirmed {
                    model.restoreOnboardingScheduleConfirmation()
                }
            }
            Button {
                save()
            } label: {
                if isSaving {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving…")
                    }
                } else {
                    Text(requiresOnboardingConfirmation ? "Save & Confirm" : "Save Schedule")
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isSaving)
            .accessibilityIdentifier("schedule.save")
        }
    }

    private var weeklySummary: String {
        var groups: [(weekdays: [Weekday], rule: DayRule)] = []
        for weekday in orderedWeekdays {
            let rule = rules[weekday] ?? .blockedAllDay
            if let lastIndex = groups.indices.last,
               groups[lastIndex].rule == rule {
                groups[lastIndex].weekdays.append(weekday)
            } else {
                groups.append(([weekday], rule))
            }
        }
        return groups.map { group in
            "\(weekdayRangeName(group.weekdays)) · \(ruleSummary(group.rule))"
        }
        .joined(separator: "   •   ")
    }

    private func weekdayRangeName(_ weekdays: [Weekday]) -> String {
        guard let first = weekdays.first else {
            return ""
        }
        guard let last = weekdays.last, first != last else {
            return shortWeekdayDisplayName(first)
        }
        return "\(shortWeekdayDisplayName(first))–\(shortWeekdayDisplayName(last))"
    }

    private func ruleSummary(_ rule: DayRule) -> String {
        switch rule {
        case let .scheduled(start, end, endsNextDay):
            let suffix = endsNextDay ? " next day" : ""
            return "\(formattedTime(start))–\(formattedTime(end))\(suffix)"
        case .availableAllDay:
            return "Available all day"
        case .blockedAllDay:
            return "Closed"
        }
    }

    private func formattedTime(_ time: LocalTime) -> String {
        let date = Calendar.autoupdatingCurrent.date(
            from: DateComponents(
                calendar: .autoupdatingCurrent,
                hour: time.hour,
                minute: time.minute
            )
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var orderedWeekdays: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    private func ruleBinding(for weekday: Weekday) -> Binding<DayRule> {
        Binding(
            get: { rules[weekday] ?? .blockedAllDay },
            set: {
                rules[weekday] = $0
                draftEditRevision &+= 1
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
            if model.scheduleChangeRequiresImmediateClose(schedule) {
                pendingSchedule = schedule
            } else {
                performSave(
                    schedule,
                    confirmsImmediateClose: false
                )
            }
        } catch {
            validationMessage = scheduleValidationMessage(error)
        }
    }

    private func performSave(
        _ schedule: WeeklySchedule,
        confirmsImmediateClose: Bool
    ) {
        isSaving = true
        saveErrorMessage = nil
        model.clearError()
        let submittedEditRevision = draftEditRevision
        Task { @MainActor in
            if await model.setSchedule(
                schedule,
                expectedRevision: draftRevision,
                confirmsImmediateClose: confirmsImmediateClose
            ) {
                if draftEditRevision == submittedEditRevision {
                    rules = model.configuration.schedule.rules
                }
                draftRevision = model.policyRevision
                lastSavedScheduleWasConfirmed =
                    model.configuration.onboardingScheduleConfirmed
            } else {
                saveErrorMessage = model.lastError
            }
            isSaving = false
        }
    }

    private var pendingScheduleConfirmation: Binding<Bool> {
        Binding(
            get: { pendingSchedule != nil },
            set: { if !$0 { pendingSchedule = nil } }
        )
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
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(
                    alignment: .firstTextBaseline,
                    spacing: HomewardSpacing.large
                ) {
                    Text(weekdayName)
                        .font(.headline)
                        .frame(minWidth: 92, alignment: .leading)
                    Spacer()
                    modePicker
                }
                VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                    Text(weekdayName)
                        .font(.headline)
                    modePicker
                }
            }

            if case .scheduled = rule {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Color.clear
                            .frame(width: 98, height: 1)
                            .accessibilityHidden(true)
                        timeControls
                    }
                    VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                        timeControls
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Color.clear
                            .frame(width: 98, height: 1)
                            .accessibilityHidden(true)
                        modeDescriptionText
                    }
                    modeDescriptionText
                }
            }
        }
        .padding(.vertical, HomewardSpacing.xSmall)
        .accessibilityIdentifier("schedule.day.\(weekday.rawValue)")
    }

    private var modePicker: some View {
        Picker("\(weekdayName) availability", selection: modeBinding) {
            ForEach(Mode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .labelsHidden()
        .frame(minWidth: 156, idealWidth: 168)
        .accessibilityLabel("\(weekdayName) mode")
    }

    @ViewBuilder
    private var timeControls: some View {
        DatePicker(
            "From",
            selection: timeBinding(isStart: true),
            displayedComponents: .hourAndMinute
        )
        .accessibilityLabel("\(weekdayName) start time")
        DatePicker(
            "to",
            selection: timeBinding(isStart: false),
            displayedComponents: .hourAndMinute
        )
        .accessibilityLabel("\(weekdayName) end time")
        Toggle("Ends next day", isOn: nextDayBinding)
            .toggleStyle(.checkbox)
            .accessibilityLabel("\(weekdayName) ends next day")
    }

    private var modeDescription: String {
        switch rule {
        case .scheduled:
            return ""
        case .availableAllDay:
            return "Work apps remain available for the full day."
        case .blockedAllDay:
            return "Work apps remain closed for the full day."
        }
    }

    private var modeDescriptionText: some View {
        Text(modeDescription)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
        let calendar = Calendar.current
        let fallback = calendar.startOfDay(
            for: Date(timeIntervalSinceReferenceDate: 0)
        )
        return calendar.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        ) ?? fallback
    }
}

private func weekdayDisplayName(_ weekday: Weekday) -> String {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale.autoupdatingCurrent
    return calendar.weekdaySymbols[weekday.rawValue - 1]
}

private func shortWeekdayDisplayName(_ weekday: Weekday) -> String {
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = Locale.autoupdatingCurrent
    return calendar.shortWeekdaySymbols[weekday.rawValue - 1]
}
