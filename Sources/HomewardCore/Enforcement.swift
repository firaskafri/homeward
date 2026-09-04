import Foundation

public struct ProcessSessionID: RawRepresentable, Codable, Equatable, Hashable,
    Sendable, CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(processIdentifier: Int32, launchedAt: Date) {
        rawValue = "\(processIdentifier)-\(launchedAt.timeIntervalSinceReferenceDate)"
    }

    public var description: String { rawValue }
}

public struct RunningApplicationSnapshot: Equatable, Sendable {
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

    public var processSessionID: ProcessSessionID? {
        guard let launchedAt else {
            return nil
        }
        return ProcessSessionID(
            processIdentifier: processIdentifier,
            launchedAt: launchedAt
        )
    }
}

public struct EnforcementTarget: Equatable, Sendable {
    public let id: ProcessSessionID
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

public struct EnforcementIdentity: Equatable, Sendable {
    public let targetID: ProcessSessionID
    public let selectionID: UUID
    public let schedule: WeeklySchedule
    public let blockedIntervalID: String

    public init(
        target: EnforcementTarget,
        schedule: WeeklySchedule,
        blockedIntervalID: String
    ) {
        targetID = target.id
        selectionID = target.selectionID
        self.schedule = schedule
        self.blockedIntervalID = blockedIntervalID
    }

    public func isCurrent(
        schedule: WeeklySchedule,
        blockedIntervalID: String,
        targets: [EnforcementTarget]
    ) -> Bool {
        self.schedule == schedule
            && self.blockedIntervalID == blockedIntervalID
            && targets.contains {
                $0.id == targetID && $0.selectionID == selectionID
            }
    }
}

public struct EnforcementSession: Equatable, Sendable {
    public static let firmGracePeriod = HomewardPolicy.firmGracePeriod

    public let mode: CloseMode
    public let startedAt: Date
    public var targets: [ProcessSessionID: EnforcementTarget]
    public var forceEscalationPaused: Bool

    public init(
        mode: CloseMode,
        startedAt: Date,
        targets: [EnforcementTarget],
        forceEscalationPaused: Bool = false
    ) {
        self.mode = mode
        self.startedAt = startedAt
        self.forceEscalationPaused = forceEscalationPaused
        self.targets = targets.reduce(into: [:]) { result, target in
            result[target.id] = target
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
        for selection in selections
        where selection.isResolvable && !selection.isProtected {
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
    ) -> [ProcessSessionID] {
        guard session.mode == .firm,
              !session.forceEscalationPaused,
              !schedule.isAvailable
        else {
            return []
        }

        let selectionsByID = currentSelections.reduce(
            into: [UUID: SelectedApplication]()
        ) {
            $0[$1.id] = $1
        }
        let runningBySessionID = currentlyRunning.reduce(
            into: [ProcessSessionID: RunningApplicationSnapshot]()
        ) {
            if let sessionID = $1.processSessionID {
                $0[sessionID] = $1
            }
        }
        let forceDeadline = session.startedAt.addingTimeInterval(
            EnforcementSession.firmGracePeriod
        )

        return session.targets.values.compactMap { target in
            guard now >= forceDeadline,
                  let selection = selectionsByID[target.selectionID],
                  selection.isResolvable,
                  !selection.isProtected,
                  let liveProcess = runningBySessionID[target.id],
                  liveProcess == target.process,
                  matches(selection: selection, process: liveProcess)
            else {
                return nil
            }
            return target.id
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
