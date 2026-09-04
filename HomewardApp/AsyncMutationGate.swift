import Foundation

@MainActor
final class AsyncMutationGate {
    private(set) var isInProgress = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilAvailable() async {
        while isInProgress {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    func beginIfAvailable() -> Bool {
        guard !isInProgress else {
            return false
        }
        isInProgress = true
        return true
    }

    func beginAfterWaiting() async {
        await waitUntilAvailable()
        isInProgress = true
    }

    func finish() {
        precondition(isInProgress)
        isInProgress = false
        let waiting = waiters
        waiters.removeAll()
        waiting.forEach { $0.resume() }
    }
}
