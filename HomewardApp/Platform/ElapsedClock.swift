import Foundation

@MainActor
struct ElapsedClock {
    typealias Instant = ContinuousClock.Instant

    let now: () -> Instant
    let sleep: (Duration) async throws -> Void

    static var continuous: ElapsedClock {
        let clock = ContinuousClock()
        return ElapsedClock(
            now: { clock.now },
            sleep: { duration in
                try await clock.sleep(for: duration)
            }
        )
    }

    func seconds(until deadline: Instant) -> Double {
        let components = now().duration(to: deadline).components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
