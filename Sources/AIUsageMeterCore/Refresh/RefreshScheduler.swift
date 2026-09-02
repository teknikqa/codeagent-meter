import Foundation

/// Fixed-interval refresh loop. CodexBar's adaptive/backoff scheduler is
/// deliberately not built here — this is intentionally the simplest thing
/// that works for MVP.
@MainActor
public final class RefreshScheduler {
    private var timer: Timer?
    private let intervalSeconds: TimeInterval
    private let onFire: @Sendable () async -> Void

    public init(intervalSeconds: TimeInterval, onFire: @escaping @Sendable () async -> Void) {
        self.intervalSeconds = intervalSeconds
        self.onFire = onFire
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [onFire] _ in
            Task { await onFire() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}
