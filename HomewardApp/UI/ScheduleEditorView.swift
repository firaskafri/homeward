import HomewardCore
import SwiftUI

struct ScheduleEditorView: View {
    @ObservedObject var model: AppModel
    let requiresOnboardingConfirmation: Bool
    let onSuccessfulOnboardingSave: () -> Void
    @State private var rules: [Weekday: DayRule]
    @State private var expandedWeekday: Weekday?
    @State private var validation: ScheduleValidationPresentation?
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @State private var copySource: Weekday = .monday
    @State private var pendingSchedule: WeeklySchedule?
    @State private var lastSavedScheduleWasConfirmed: Bool
    @State private var draftRevision: Int
    @State private var draftEditRevision = 0
    @State private var showsCopyTools = false
    @AccessibilityFocusState private var validationErrorFocused: Bool

    init(
        model: AppModel,
        requiresOnboardingConfirmation: Bool = false,
        onSuccessfulOnboardingSave: @escaping () -> Void = {}
    ) {
        self.model = model
        self.requiresOnboardingConfirmation = requiresOnboardingConfirmation
        self.onSuccessfulOnboardingSave = onSuccessfulOnboardingSave
        _rules = State(initialValue: model.configuration.schedule.rules)
        _lastSavedScheduleWasConfirmed = State(
            initialValue: model.configuration.onboardingScheduleConfirmed
        )
        _draftRevision = State(initialValue: model.policyRevision)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if !requiresOnboardingConfirmation {
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
                }

                Section("This week") {
                    ForEach(
                        Array(weeklySummaryLines.enumerated()),
                        id: \.offset
                    ) { _, summary in
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    ForEach(orderedWeekdays, id: \.self) { weekday in
                        DayRuleRow(
                            weekday: weekday,
                            rule: rules[weekday] ?? .blockedAllDay,
                            isExpanded: expandedWeekday == weekday,
                            toggleExpansion: {
                                expandedWeekday =
                                    expandedWeekday == weekday
                                    ? nil
                                    : weekday
                            }
                        )
                    }
                } header: {
                    Text("Daily availability")
                } footer: {
                    Text("Overnight hours belong to the day on which they begin.")
                }

                if let expandedWeekday {
                    Section(
                        "Edit \(ScheduleEditorPresentation.weekdayName(expandedWeekday))"
                    ) {
                        DayRuleFields(
                            weekday: expandedWeekday,
                            rule: ruleBinding(for: expandedWeekday)
                        )
                    }
                }

                if let validation {
                    Section {
                        Label(
                            validation.message,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("schedule.validation")
                        .accessibilityFocused($validationErrorFocused)
                    }
                }

                Section {
                    DisclosureGroup(
                        "Copy a day’s schedule",
                        isExpanded: $showsCopyTools
                    ) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: HomewardSpacing.large) {
                                copySourcePicker
                                Spacer(minLength: HomewardSpacing.large)
                                copyDestinationMenu
                            }
                            VStack(
                                alignment: .leading,
                                spacing: HomewardSpacing.small
                            ) {
                                copySourcePicker
                                copyDestinationMenu
                            }
                        }
                        .padding(.top, HomewardSpacing.small)
                    }
                    .accessibilityIdentifier("schedule.copy.disclosure")
                }

                if let saveErrorMessage {
                    Section {
                        InlineErrorView(message: saveErrorMessage) {
                            self.saveErrorMessage = nil
                            model.clearError()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: HomewardMetrics.scheduleFormMaxWidth)
            .frame(maxWidth: .infinity)

            Divider()

            actionBar
                .frame(maxWidth: HomewardMetrics.scheduleFormMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, HomewardSpacing.large)
                .padding(.vertical, HomewardSpacing.medium)
                .background(.bar)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("schedule.actions")
        }
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
        .onChange(of: model.policyRevision) { _, revision in
            guard !hasDraftChanges, !isSaving else {
                return
            }
            rules = model.configuration.schedule.rules
            draftRevision = revision
            lastSavedScheduleWasConfirmed =
                model.configuration.onboardingScheduleConfirmed
        }
        .accessibilityIdentifier("schedule.view")
    }

    private var copySourcePicker: some View {
        Picker("Copy from", selection: $copySource) {
            ForEach(orderedWeekdays, id: \.self) { weekday in
                Text(ScheduleEditorPresentation.weekdayName(weekday))
                    .tag(weekday)
            }
        }
        .fixedSize()
        .accessibilityIdentifier("schedule.copy.source")
    }

    private var copyDestinationMenu: some View {
        Menu(
            "Copy \(ScheduleEditorPresentation.weekdayName(copySource)) to…"
        ) {
            ForEach(
                orderedWeekdays.filter { $0 != copySource },
                id: \.self
            ) { weekday in
                Button(
                    "Copy \(ScheduleEditorPresentation.weekdayName(copySource)) "
                        + "to \(ScheduleEditorPresentation.weekdayName(weekday))"
                ) {
                    copyRule(to: weekday)
                }
            }
        }
        .accessibilityIdentifier("schedule.copy.destination")
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HomewardSpacing.large) {
                saveStatus
                Spacer(minLength: HomewardSpacing.large)
                scheduleActions
            }
            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                saveStatus
                scheduleActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var saveStatus: some View {
        if hasDraftChanges {
            HomewardStatusLabel(
                title: "Unsaved changes",
                symbol: "circle.fill",
                tone: .attention
            )
        } else if onboardingNeedsConfirmation {
            HomewardStatusLabel(
                title: "Ready to save",
                symbol: "circle.dashed",
                tone: .attention
            )
        } else {
            HomewardStatusLabel(
                title: "Saved",
                symbol: "checkmark.circle",
                tone: .neutral
            )
        }
    }

    private var scheduleActions: some View {
        HStack {
            Button("Reset Draft") {
                resetDraft()
            }
            .disabled(!hasDraftChanges || isSaving)
            .accessibilityIdentifier("schedule.reset")

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
                    Text(
                        requiresOnboardingConfirmation
                            ? "Save & Continue"
                            : "Save Schedule"
                    )
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isSaving || !canSave)
            .accessibilityIdentifier("schedule.save")
        }
    }

    private var orderedWeekdays: [Weekday] {
        ScheduleEditorPresentation.orderedWeekdays
    }

    private var weeklySummaryLines: [String] {
        ScheduleEditorPresentation.weeklySummaryLines(rules: rules)
    }

    private var hasDraftChanges: Bool {
        rules != model.configuration.schedule.rules
    }

    private var onboardingNeedsConfirmation: Bool {
        requiresOnboardingConfirmation
            && !model.configuration.onboardingScheduleConfirmed
    }

    private var canSave: Bool {
        hasDraftChanges || onboardingNeedsConfirmation
    }

    private func ruleBinding(for weekday: Weekday) -> Binding<DayRule> {
        Binding(
            get: { rules[weekday] ?? .blockedAllDay },
            set: {
                rules[weekday] = $0
                draftEditRevision &+= 1
                validation = nil
                validationErrorFocused = false
                if requiresOnboardingConfirmation {
                    model.markOnboardingScheduleDirty()
                }
            }
        )
    }

    private func copyRule(to weekday: Weekday) {
        guard let sourceRule = rules[copySource] else {
            return
        }
        rules[weekday] = sourceRule
        draftEditRevision &+= 1
        validation = nil
        validationErrorFocused = false
        if requiresOnboardingConfirmation {
            model.markOnboardingScheduleDirty()
        }
    }

    private func resetDraft() {
        rules = model.configuration.schedule.rules
        draftRevision = model.policyRevision
        draftEditRevision &+= 1
        validation = nil
        validationErrorFocused = false
        saveErrorMessage = nil
        if requiresOnboardingConfirmation,
           lastSavedScheduleWasConfirmed {
            model.restoreOnboardingScheduleConfirmation()
        }
    }

    private func save() {
        validation = nil
        validationErrorFocused = false
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
            let presentation = ScheduleEditorPresentation.validation(for: error)
            validation = presentation
            if let weekday = presentation.weekday {
                expandedWeekday = weekday
            }
            Task { @MainActor in
                await Task.yield()
                validationErrorFocused = true
            }
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
                isSaving = false
                if requiresOnboardingConfirmation {
                    onSuccessfulOnboardingSave()
                }
            } else {
                saveErrorMessage = model.lastError
                isSaving = false
            }
        }
    }

    private var pendingScheduleConfirmation: Binding<Bool> {
        Binding(
            get: { pendingSchedule != nil },
            set: { if !$0 { pendingSchedule = nil } }
        )
    }
}

private struct DayRuleRow: View {
    let weekday: Weekday
    let rule: DayRule
    let isExpanded: Bool
    let toggleExpansion: () -> Void

    var body: some View {
        Button(action: toggleExpansion) {
            HStack(spacing: HomewardSpacing.medium) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(weekdayName)
                            .font(.headline)
                        Spacer(minLength: HomewardSpacing.large)
                        Text(ruleSummary)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(weekdayName)
                            .font(.headline)
                        Text(ruleSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, HomewardSpacing.xSmall)
        .accessibilityLabel("\(weekdayName), \(ruleSummary)")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(
            isExpanded ? "Collapses \(weekdayName)" : "Expands \(weekdayName)"
        )
        .accessibilityIdentifier("\(identifierPrefix).disclosure")
    }

    private var weekdayName: String {
        ScheduleEditorPresentation.weekdayName(weekday)
    }

    private var ruleSummary: String {
        ScheduleEditorPresentation.ruleSummary(rule, for: weekday)
    }

    private var identifierPrefix: String {
        "schedule.day.\(ScheduleEditorPresentation.identifier(for: weekday))"
    }
}

private struct DayRuleFields: View {
    enum Mode: String, CaseIterable, Identifiable {
        case scheduled = "Scheduled hours"
        case availableAllDay = "Available all day"
        case blockedAllDay = "Closed all day"

        var id: String { rawValue }
    }

    let weekday: Weekday
    @Binding var rule: DayRule

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalFields
            stackedFields
        }
        .controlSize(.small)
        .padding(.vertical, HomewardSpacing.xSmall)
    }

    @ViewBuilder
    private var horizontalFields: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.small) {
            HStack(
                alignment: .firstTextBaseline,
                spacing: HomewardSpacing.large
            ) {
                horizontalModePicker
                if isScheduled {
                    horizontalStartPicker
                    horizontalEndPicker
                }
            }
            if isScheduled {
                overnightToggle
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var stackedFields: some View {
        VStack(alignment: .leading, spacing: HomewardSpacing.small) {
            LabeledContent("Availability") {
                modeMenu
            }
            if isScheduled {
                LabeledContent("From") {
                    startPicker
                }
                LabeledContent("Until") {
                    endPicker
                }
                overnightToggle
            }
        }
    }

    private var horizontalModePicker: some View {
        Picker("Availability", selection: modeBinding) {
            modeOptions
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Availability, \(weekdayName)")
        .accessibilityValue(modeBinding.wrappedValue.rawValue)
        .accessibilityIdentifier("\(identifierPrefix).mode")
    }

    private var modeMenu: some View {
        Picker("", selection: modeBinding) {
            modeOptions
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel("Availability, \(weekdayName)")
        .accessibilityValue(modeBinding.wrappedValue.rawValue)
        .accessibilityIdentifier("\(identifierPrefix).mode")
    }

    private var modeOptions: some View {
        ForEach(Mode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
        }
    }

    private var horizontalStartPicker: some View {
        DatePicker(
            "From",
            selection: timeBinding(isStart: true),
            displayedComponents: .hourAndMinute
        )
        .fixedSize()
        .accessibilityLabel("From, \(weekdayName)")
        .accessibilityIdentifier("\(identifierPrefix).start")
    }

    private var startPicker: some View {
        DatePicker(
            "",
            selection: timeBinding(isStart: true),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("From, \(weekdayName)")
        .accessibilityIdentifier("\(identifierPrefix).start")
    }

    private var horizontalEndPicker: some View {
        DatePicker(
            "Until",
            selection: timeBinding(isStart: false),
            displayedComponents: .hourAndMinute
        )
        .fixedSize()
        .accessibilityLabel("Until, \(weekdayName)")
        .accessibilityIdentifier("\(identifierPrefix).end")
    }

    private var endPicker: some View {
        DatePicker(
            "",
            selection: timeBinding(isStart: false),
            displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Until, \(weekdayName)")
        .accessibilityIdentifier("\(identifierPrefix).end")
    }

    private var overnightToggle: some View {
        Toggle(
            "Ends \(ScheduleEditorPresentation.weekdayName(destinationWeekday))",
            isOn: nextDayBinding
        )
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("\(identifierPrefix).overnight")
    }

    private var weekdayName: String {
        ScheduleEditorPresentation.weekdayName(weekday)
    }

    private var destinationWeekday: Weekday {
        ScheduleEditorPresentation.nextWeekday(after: weekday)
    }

    private var identifierPrefix: String {
        "schedule.day.\(ScheduleEditorPresentation.identifier(for: weekday))"
    }

    private var isScheduled: Bool {
        if case .scheduled = rule {
            return true
        }
        return false
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
                let components = Calendar.current.dateComponents(
                    [.hour, .minute],
                    from: date
                )
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
                rule = .scheduled(
                    start: start,
                    end: end,
                    endsNextDay: value
                )
            }
        )
    }

    private func referenceDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let fallback = calendar.startOfDay(
            for: Date(timeIntervalSinceReferenceDate: 0)
        )
        return calendar.date(
            from: DateComponents(
                year: 2001,
                month: 1,
                day: 1,
                hour: hour,
                minute: minute
            )
        ) ?? fallback
    }
}
