import Foundation

public struct RunningApplicationSnapshot: Equatable, Hashable, Sendable {
    public let processIdentifier: Int32
    public let bundleIdentifier: String?
    public let bundlePath: String?
    public let displayName: String
    public let launchedAt: Date?

    public init(
        processIdentifier: Int32,
        bundleIdentifier: String?,
        bundlePath: String?,
        displayName: String,
        launchedAt: Date?
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.launchedAt = launchedAt
    }

    public var processSessionID: String? {
        guard let launchedAt else {
            return nil
        }
        return "\(processIdentifier)-\(launchedAt.timeIntervalSinceReferenceDate)"
    }
}

public struct EnforcementTarget: Equatable, Identifiable, Sendable {
    public let id: String
    public let selectionID: UUID
    public let process: RunningApplicationSnapshot

    public init(
        selectionID: UUID,
        process: RunningApplicationSnapshot
    ) throws {
        guard let processSessionID = process.processSessionID else {
            throw EnforcementError.missingProcessIdentity
        }
        self.id = processSessionID
        self.selectionID = selectionID
        self.process = process
    }
}

public enum TargetOutcome: String, Codable, Equatable, Sendable {
    case awaitingNormalQuit
    case awaitingForceDeadline
    case unresolved
    case exempted
    case terminated
}

public struct TargetEnforcementState: Equatable, Sendable {
    public let target: EnforcementTarget
    public var outcome: TargetOutcome
    public var forceDeadline: Date?

    public init(
        target: EnforcementTarget,
        outcome: TargetOutcome = .awaitingNormalQuit,
        forceDeadline: Date? = nil
    ) {
        self.target = target
        self.outcome = outcome
        self.forceDeadline = forceDeadline
    }
}

public struct EnforcementSession: Equatable, Identifiable, Sendable {
    public static let firmGracePeriod: TimeInterval = 30

    public let id: UUID
    public let blockedIntervalID: String
    public let mode: CloseMode
    public let startedAt: Date
    public var targets: [String: TargetEnforcementState]
    public var forceEscalationPaused: Bool

    public init(
        id: UUID = UUID(),
        blockedIntervalID: String,
        mode: CloseMode,
        startedAt: Date,
        targets: [EnforcementTarget],
        forceEscalationPaused: Bool = false
    ) {
        self.id = id
        self.blockedIntervalID = blockedIntervalID
        self.mode = mode
        self.startedAt = startedAt
        self.forceEscalationPaused = forceEscalationPaused
        self.targets = Dictionary(
            uniqueKeysWithValues: targets.map { target in
                let deadline = mode == .firm
                    ? startedAt.addingTimeInterval(Self.firmGracePeriod)
                    : nil
                let state = TargetEnforcementState(
                    target: target,
                    outcome: mode == .firm ? .awaitingForceDeadline : .awaitingNormalQuit,
                    forceDeadline: deadline
                )
                return (target.id, state)
            }
        )
    }

    public var isComplete: Bool {
        targets.values.allSatisfy { state in
            state.outcome == .terminated || state.outcome == .exempted
        }
    }
}

public struct EnforcementPlanner: Sendable {
    public init() {}

    public func targets(
        selections: [SelectedApplication],
        runningApplications: [RunningApplicationSnapshot]
    ) -> [EnforcementTarget] {
        var targets: [EnforcementTarget] = []
        for selection in selections where !selection.isProtected {
            for process in runningApplications where matches(selection: selection, process: process) {
                guard let target = try? EnforcementTarget(
                    selectionID: selection.id,
                    process: process
                ) else {
                    continue
                }
                targets.append(target)
            }
        }
        return targets
    }

    public func forceEligibleTargetIDs(
        session: EnforcementSession,
        at now: Date,
        schedule: ResolvedSchedule,
        currentSelections: [SelectedApplication],
        currentlyRunning: [RunningApplicationSnapshot]
    ) -> [String] {
        guard session.mode == .firm,
              !session.forceEscalationPaused,
              !schedule.isAvailable
        else {
            return []
        }

        let selectionsByID = Dictionary(
            uniqueKeysWithValues: currentSelections.map { ($0.id, $0) }
        )
        let runningBySessionID = Dictionary(
            uniqueKeysWithValues: currentlyRunning.compactMap { snapshot in
                snapshot.processSessionID.map { ($0, snapshot) }
            }
        )

        return session.targets.values.compactMap { state in
            guard state.outcome == .awaitingForceDeadline,
                  let deadline = state.forceDeadline,
                  now >= deadline,
                  let selection = selectionsByID[state.target.selectionID],
                  let liveProcess = runningBySessionID[state.target.id],
                  liveProcess == state.target.process,
                  matches(selection: selection, process: liveProcess)
            else {
                return nil
            }
            return state.target.id
        }
    }

    public func matches(
        selection: SelectedApplication,
        process: RunningApplicationSnapshot
    ) -> Bool {
        if let selectedBundleID = selection.bundleIdentifier {
            return process.bundleIdentifier == selectedBundleID
        }
        guard let processPath = process.bundlePath else {
            return false
        }
        let selectedPath = URL(fileURLWithPath: selection.bundlePath)
            .standardizedFileURL.path
        let runningPath = URL(fileURLWithPath: processPath)
            .standardizedFileURL.path
        return selectedPath == runningPath
    }
}

public enum EnforcementError: Error, Equatable, Sendable {
    case missingProcessIdentity
}

public struct CountdownAnnouncementPolicy: Sendable {
    public static let milestones: Set<Int> = [30, 15, 5]

    public init() {}

    public func shouldAnnounce(
        secondsRemaining: Int,
        announced: Set<Int>
    ) -> Bool {
        Self.milestones.contains(secondsRemaining)
            && !announced.contains(secondsRemaining)
    }
}
