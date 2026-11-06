import Foundation

/// Refresh loop whose wait is re-evaluated after every run, so the interval
/// can adapt (see `RefreshPolicy`).
@MainActor
public final class RefreshScheduler {
    private var task: Task<Void, Never>?
    private let nextInterval: @MainActor () -> TimeInterval
    private let onFire: @Sendable () async -> Void

    public init(
        nextInterval: @escaping @MainActor () -> TimeInterval,
        onFire: @escaping @Sendable () async -> Void
    ) {
        self.nextInterval = nextInterval
        self.onFire = onFire
    }

    public func start() {
        stop()
        task = Task { [nextInterval, onFire] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(nextInterval() * 1_000_000_000))
                if Task.isCancelled { break }
                await onFire()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
