// Packages/FeedbackKit/Sources/FeedbackKit/HoverDelay.swift
import Foundation

/// Fork: a one-shot timer for the hover preview (#265). A menu runs its own
/// event loop in event tracking mode, and a timer in the default mode alone
/// never fires while a menu is open. This timer joins the common modes, which
/// include event tracking. Starting it again replaces the pending fire.
@MainActor
public final class HoverDelay {
    public let delay: TimeInterval
    private var timer: Timer?

    public init(delay: TimeInterval = HoverPreviewPolicy.delay) {
        self.delay = delay
    }

    public var isPending: Bool { timer != nil }

    public func start(_ fire: @escaping @MainActor () -> Void) {
        cancel()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                // A delay that is gone fires nothing.
                guard let self else { return }
                self.timer = nil
                fire()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
