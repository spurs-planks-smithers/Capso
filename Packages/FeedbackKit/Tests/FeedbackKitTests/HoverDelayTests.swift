import Foundation
import Testing
@testable import FeedbackKit

/// A menu runs its event loop in event tracking mode. A timer in the default
/// mode alone never fires while a menu is open. AppKit puts that mode in the
/// common set, but a test process may not load AppKit, so these tests join a
/// stand-in mode to the common set and spin the loop in it. A timer in the
/// default mode alone never fires there.
@MainActor
@Suite("HoverDelay")
struct HoverDelayTests {
    private static let trackingMode: RunLoop.Mode = {
        let mode = RunLoop.Mode("HoverDelayTests.tracking")
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(mode.rawValue as CFString))
        return mode
    }()

    private func spin(_ seconds: TimeInterval, mode: RunLoop.Mode) {
        RunLoop.main.run(mode: mode, before: Date(timeIntervalSinceNow: seconds))
    }

    @Test("Fires in event tracking mode, as during menu tracking")
    func firesWhileTracking() {
        let delay = HoverDelay(delay: 0.05)
        var fired = 0
        delay.start { fired += 1 }
        #expect(delay.isPending)
        spin(0.4, mode: Self.trackingMode)
        #expect(fired == 1)
        #expect(delay.isPending == false)
    }

    @Test("Fires in the default mode too")
    func firesInDefaultMode() {
        let delay = HoverDelay(delay: 0.05)
        var fired = 0
        delay.start { fired += 1 }
        spin(0.4, mode: .default)
        #expect(fired == 1)
    }

    @Test("Cancel stops a pending fire")
    func cancel() {
        let delay = HoverDelay(delay: 0.05)
        var fired = 0
        delay.start { fired += 1 }
        delay.cancel()
        #expect(delay.isPending == false)
        spin(0.3, mode: Self.trackingMode)
        #expect(fired == 0)
    }

    @Test("A second start replaces the first")
    func restart() {
        let delay = HoverDelay(delay: 0.05)
        var first = 0
        var second = 0
        delay.start { first += 1 }
        delay.start { second += 1 }
        spin(0.4, mode: Self.trackingMode)
        #expect(first == 0)
        #expect(second == 1)
    }

    @Test("The default delay is the policy delay")
    func defaultDelay() {
        #expect(HoverDelay().delay == HoverPreviewPolicy.delay)
    }
}
