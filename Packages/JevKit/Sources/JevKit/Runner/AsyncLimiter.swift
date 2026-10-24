// Packages/JevKit/Sources/JevKit/Runner/AsyncLimiter.swift
import Foundation

/// Lets at most `limit` callers run at once. The others wait in order. A
/// waiter whose task is cancelled leaves the queue at once.
actor AsyncLimiter {
    private var available: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) {
        available = max(limit, 1)
    }

    func acquire() async throws {
        if available > 0 {
            available -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        guard let position = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: position).continuation.resume(throwing: CancellationError())
    }
}
