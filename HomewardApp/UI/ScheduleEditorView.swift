import HomewardCore
import SwiftUI

struct ScheduleEditorView: View {
    @ObservedObject var model: AppModel
    let requiresOnboardingConfirmation: Bool
    let onSuccessfulOnboardingSave: () -> Void
    @State private var rules: [Weekday: DayRule]
    @State private var selectedWeekday: Weekday = .monday
    @State private var validation: ScheduleValidationPresentation?
    @State private var saveErrorMessage: String?
    @State private var isSaving = false
    @State private var pendingSchedule: WeeklySchedule?
    @State private var lastSavedScheduleWasConfirmed: Bool
    @State private var draftRevision: Int
    @State private var draftEditRevision = 0
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
            ScrollView {
                VStack(alignment: .leading, spacing: HomewardSpacing.large) {
                    if !requiresOnboardingConfirmation {
                        scheduleIntroduction
                    }

                    weekCard
                    dayEditorCard

                    if let validation {
                        validationCard(validation)
                    }

                    if let saveErrorMessage {
                        HomewardCard {
                            InlineErrorView(message: saveErrorMessage) {
                                self.saveErrorMessage = nil
                                model.clearError()
                            }
                        }
                    }
                }
                .padding(HomewardSpacing.xLarge)
                .frame(
                    maxWidth: HomewardMetrics.scheduleFormMaxWidth,
                    alignment: .leading
                )
                .frame(maxWidth: .infinity)
            }
            .disabled(isSaving)

            Divider()

            actionBar
                .frame(maxWidth: HomewardMetrics.scheduleFormMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, HomewardSpacing.large)
                .padding(.vertical, HomewardSpacing.medium)
                .background(.bar)
                .accessibilityElement(children: .contain)
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
                SchedulePresentation.immediateClosingMessage(
                    context:
                        "This change makes the current time unavailable.",
                    closeMode: model.configuration.closeMode
                )
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
    }

    private var scheduleIntroduction: some View {
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
        .accessibilityElement(children: .combine)
    }

    private var weekCard: some View {
        HomewardCard {
            VStack(alignment: .leading, spacing: HomewardSpacing.medium) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your week")
                            .font(.headline)
                            .accessibilityIdentifier("schedule.view")
                        Text(weekSummary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(HomewardTone.rest.color)
                        .accessibilityHidden(true)
                }

                HStack(spacing: HomewardSpacing.small) {
                    ForEach(orderedWeekdays, id: \.self) { weekday in
                        WeekdayScheduleButton(
                            weekday: weekday,
                            rule: rules[weekday] ?? .blockedAllDay,
                            isSelected: selectedWeekday == weekday
                        ) {
                            withAnimation(.easeOut(duration: 0.16)) {
                                selectedWeekday = weekday
                            }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private var dayEditorCard: some View {
        HomewardCard {
            VStack(alignment: .leading, spacing: HomewardSpacing.large) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) {
                        selectedDayHeading
                        Spacer(minLength: HomewardSpacing.large)
                        copyDestinationMenu
                    }
                    VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                        selectedDayHeading
                        copyDestinationMenu
                    }
                }

                DayRuleFields(
                    weekday: selectedWeekday,
                    rule: ruleBinding(for: selectedWeekday)
                )

                Divider()

                Label(
                    "Overnight hours belong to the day on which they begin.",
                    systemImage: "moon.stars"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedDayHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ScheduleEditorPresentation.weekdayName(selectedWeekday))
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text(
                ScheduleEditorPresentation.ruleSummary(
                    rules[selectedWeekday] ?? .blockedAllDay,
                    for: selectedWeekday
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func validationCard(
        _ validation: ScheduleValidationPresentation
    ) -> some View {
        HomewardCard {
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

    private var copyDestinationMenu: some View {
        Menu {
            Button("Weekdays") {
                copySelectedRule(to: [
                    .monday,
                    .tuesday,
                    .wednesday,
                    .thursday,
                    .friday,
                ])
            }
            Button("Weekend") {
                copySelectedRule(to: [.saturday, .sunday])
            }
            Button("Every day") {
                copySelectedRule(to: orderedWeekdays)
            }
            Divider()
            ForEach(
                orderedWeekdays.filter { $0 != selectedWeekday },
                id: \.self
            ) { weekday in
                Button(ScheduleEditorPresentation.weekdayName(weekday)) {
                    copySelectedRule(to: [weekday])
                }
            }
        } label: {
            Label("Apply to…", systemImage: "square.on.square")
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
                if requiresOnboardingConfirmation, !canSave {
                    onSuccessfulOnboardingSave()
                } else {
                    save()
                }
            } label: {
                if isSaving {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving…")
                    }
                } else {
                    Text(
                        primaryActionTitle
                    )
                }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(
                isSaving
                    || (!requiresOnboardingConfirmation && !canSave)
            )
            .accessibilityIdentifier("schedule.save")
        }
    }

    private var orderedWeekdays: [Weekday] {
        ScheduleEditorPresentation.orderedWeekdays
    }

    private var weekSummary: String {
        ScheduleEditorPresentation.weekSummary(rules: rules)
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

    private var primaryActionTitle: String {
        guard requiresOnboardingConfirmation else {
            return "Save Schedule"
        }
        return canSave ? "Save & Continue" : "Continue"
    }

    private func ruleBinding(for weekday: Weekday) -> Binding<DayRule> {
        Binding(
            get: { rules[weekday] ?? .blockedAllDay },
            set: {
                rules[weekday] = $0
                markDraftChanged()
            }
        )
    }

    private func copySelectedRule(to weekdays: [Weekday]) {
        guard let sourceRule = rules[selectedWeekday] else {
            return
        }
        let destinations = weekdays.filter {
            $0 != selectedWeekday && rules[$0] != sourceRule
        }
        guard !destinations.isEmpty else {
            return
        }
        for weekday in destinations {
            rules[weekday] = sourceRule
        }
        markDraftChanged()
    }

    private func markDraftChanged() {
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
                selectedWeekday = weekday
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
            defer { isSaving = false }
            if await model.setSchedule(
                schedule,
                expectedRevision: draftRevision,
                confirmsImmediateClose: confirmsImmediateClose
            ) {
                let submittedDraftIsCurrent =
                    draftEditRevision == submittedEditRevision
                if submittedDraftIsCurrent {
                    rules = model.configuration.schedule.rules
                }
                draftRevision = model.policyRevision
                lastSavedScheduleWasConfirmed =
                    model.configuration.onboardingScheduleConfirmed
                if requiresOnboardingConfirmation,
                   submittedDraftIsCurrent {
                    onSuccessfulOnboardingSave()
                }
            } else {
                saveErrorMessage = model.lastError
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

private struct WeekdayScheduleButton: View {
    let weekday: Weekday
    let rule: DayRule
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(shortWeekdayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? selectedForeground : .secondary)

                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? selectedForeground : tone)
                    .frame(height: 18)
                    .accessibilityHidden(true)

                Text(compactSummary)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isSelected ? selectedForeground : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .padding(.horizontal, 4)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(weekdayName), \(ruleSummary)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Shows \(weekdayName) schedule controls")
        .accessibilityIdentifier("\(identifierPrefix).selector")
    }

    private var weekdayName: String {
        ScheduleEditorPresentation.weekdayName(weekday)
    }

    private var shortWeekdayName: String {
        ScheduleEditorPresentation.shortWeekdayName(weekday)
    }

    private var ruleSummary: String {
        ScheduleEditorPresentation.ruleSummary(rule, for: weekday)
    }

    private var compactSummary: String {
        ScheduleEditorPresentation.compactRuleSummary(rule)
    }

    private var symbol: String {
        switch rule {
        case .scheduled:
            "clock.fill"
        case .availableAllDay:
            "sun.max.fill"
        case .blockedAllDay:
            "moon.fill"
        }
    }

    private var tone: Color {
        switch rule {
        case .scheduled:
            HomewardTone.rest.color
        case .availableAllDay:
            HomewardTone.ready.color
        case .blockedAllDay:
            .secondary
        }
    }

    private var background: Color {
        if isSelected {
            return HomewardTone.rest.color.opacity(
                colorSchemeContrast == .increased ? 0.28 : 0.16
            )
        }
        return Color.primary.opacity(0.035)
    }

    private var borderColor: Color {
        if isSelected {
            return HomewardTone.rest.color.opacity(0.85)
        }
        return Color.primary.opacity(
            colorSchemeContrast == .increased ? 0.3 : 0.1
        )
    }

    private var selectedForeground: Color {
        colorSchemeContrast == .increased ? .primary : HomewardTone.rest.color
    }

    private var identifierPrefix: String {
        ScheduleEditorPresentation.dayIdentifierPrefix(for: weekday)
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
        VStack(alignment: .leading, spacing: HomewardSpacing.small) {
            Text("Availability")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Availability", selection: modeBinding) {
                modeOptions
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .accessibilityLabel("Availability, \(weekdayName)")
            .accessibilityValue(modeBinding.wrappedValue.rawValue)
            .accessibilityIdentifier("\(identifierPrefix).mode")

            if isScheduled {
                timeRange
                    .padding(.top, HomewardSpacing.small)
                overnightControl
                    .padding(.top, HomewardSpacing.xSmall)
            } else {
                availabilityExplanation
                    .padding(.top, HomewardSpacing.small)
            }
        }
    }

    private var timeRange: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HomewardSpacing.medium) {
                startTimePicker
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                endTimePicker
            }
            VStack(alignment: .leading, spacing: HomewardSpacing.small) {
                startTimePicker
                endTimePicker
            }
        }
    }

    private var startTimePicker: some View {
        TimePickerButton(
            boundary: .start,
            identifierPrefix: identifierPrefix,
            time: timeBinding(isStart: true)
        )
    }

    private var endTimePicker: some View {
        TimePickerButton(
            boundary: .end,
            identifierPrefix: identifierPrefix,
            time: timeBinding(isStart: false)
        )
    }

    private var overnightControl: some View {
        HStack(alignment: .center, spacing: HomewardSpacing.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ends the next day")
                    .font(.callout.weight(.medium))
                Text(
                    "Use this when \(weekdayName)’s work window continues into "
                        + ScheduleEditorPresentation.weekdayName(destinationWeekday) + "."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: HomewardSpacing.large)
            Toggle(
                "Ends \(ScheduleEditorPresentation.weekdayName(destinationWeekday))",
                isOn: nextDayBinding
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(
                "Ends \(ScheduleEditorPresentation.weekdayName(destinationWeekday))"
            )
            .accessibilityIdentifier("\(identifierPrefix).overnight")
        }
    }

    private var availabilityExplanation: some View {
        Label {
            Text(
                modeBinding.wrappedValue == .availableAllDay
                    ? "Work apps remain available for the full day."
                    : "Work apps remain closed for the full day."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        } icon: {
            Image(
                systemName: modeBinding.wrappedValue == .availableAllDay
                    ? "sun.max.fill"
                    : "moon.fill"
            )
            .foregroundStyle(
                modeBinding.wrappedValue == .availableAllDay
                    ? HomewardTone.ready.color
                    : HomewardTone.rest.color
            )
        }
    }

    private var modeOptions: some View {
        ForEach(Mode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
        }
    }

    private var weekdayName: String {
        ScheduleEditorPresentation.weekdayName(weekday)
    }

    private var destinationWeekday: Weekday {
        ScheduleEditorPresentation.nextWeekday(after: weekday)
    }

    private var identifierPrefix: String {
        ScheduleEditorPresentation.dayIdentifierPrefix(for: weekday)
    }

    private var isScheduled: Bool {
        if case .scheduled = rule {
            return true
        }
        return false
    }

    private var modeBinding: Binding<Mode> {
        Binding(
            get: { currentMode },
            set: { mode in
                guard mode != currentMode else {
                    return
                }
                switch mode {
                case .scheduled:
                    do {
                        rule = try WeeklySchedule.defaultWorkdayRule()
                    } catch {
                        assertionFailure(
                            "The built-in workday rule must remain valid."
                        )
                    }
                case .availableAllDay:
                    rule = .availableAllDay
                case .blockedAllDay:
                    rule = .blockedAllDay
                }
            }
        )
    }

    private var currentMode: Mode {
        switch rule {
        case .scheduled:
            .scheduled
        case .availableAllDay:
            .availableAllDay
        case .blockedAllDay:
            .blockedAllDay
        }
    }

    private func timeBinding(isStart: Bool) -> Binding<LocalTime> {
        guard case let .scheduled(initialStart, initialEnd, _) = rule else {
            preconditionFailure("Time controls require a scheduled day rule.")
        }
        let fallback = isStart ? initialStart : initialEnd
        return Binding(
            get: {
                guard case let .scheduled(start, end, _) = rule else {
                    return fallback
                }
                return isStart ? start : end
            },
            set: { time in
                guard case let .scheduled(start, end, endsNextDay) = rule else {
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

}

private struct TimePickerButton: View {
    enum Boundary {
        case start
        case end

        var title: String {
            switch self {
            case .start:
                "Work starts"
            case .end:
                "Work ends"
            }
        }

        var identifierSuffix: String {
            switch self {
            case .start:
                "start"
            case .end:
                "end"
            }
        }
    }

    private static let minuteOptions = Array(0..<60)

    let boundary: Boundary
    let identifierPrefix: String
    @Binding var time: LocalTime
    @State private var showsPicker = false
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            showsPicker = true
        } label: {
            HStack(spacing: HomewardSpacing.medium) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(boundary.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formattedTime)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: HomewardSpacing.large)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, HomewardSpacing.medium)
            .padding(.vertical, 10)
            .frame(minWidth: 168)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(
                    cornerRadius: HomewardMetrics.compactCornerRadius
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: HomewardMetrics.compactCornerRadius
                )
                .strokeBorder(Color.primary.opacity(0.1))
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: HomewardMetrics.compactCornerRadius
                )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: HomewardSpacing.large) {
                Text(boundary.title)
                    .font(.headline)

                HStack(spacing: HomewardSpacing.small) {
                    Picker("Hour", selection: hourBinding) {
                        ForEach(
                            Array(hourLabels.enumerated()),
                            id: \.offset
                        ) { option in
                            Text(option.element).tag(option.offset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 78)

                    Text(":")
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Minute", selection: minuteBinding) {
                        ForEach(Self.minuteOptions, id: \.self) { minute in
                            Text(
                                minute.formatted(
                                    .number.precision(.integerLength(2))
                                )
                            )
                            .tag(minute)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 78)
                }

                HStack {
                    Text("Uses your Mac’s time format")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") {
                        showsPicker = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(HomewardSpacing.large)
            .frame(width: 236)
        }
        .accessibilityLabel("\(boundary.title), \(formattedTime)")
        .accessibilityHint("Opens hour and minute controls")
        .accessibilityIdentifier(
            "\(identifierPrefix).\(boundary.identifierSuffix)"
        )
    }

    private var formattedTime: String {
        ScheduleEditorPresentation.formattedTime(time, locale: locale)
    }

    private var hourLabels: [String] {
        ScheduleEditorPresentation.formattedHourLabels(locale: locale)
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { time.hour },
            set: { hour in
                guard let value = try? LocalTime(
                    hour: hour,
                    minute: time.minute
                ) else {
                    return
                }
                time = value
            }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { time.minute },
            set: { minute in
                guard let value = try? LocalTime(
                    hour: time.hour,
                    minute: minute
                ) else {
                    return
                }
                time = value
            }
        )
    }
}
