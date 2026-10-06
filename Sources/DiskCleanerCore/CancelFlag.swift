import Foundation

/// Cooperative cancel switch shared by the window and the walker.
package final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    package init() {}

    package var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    package func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
