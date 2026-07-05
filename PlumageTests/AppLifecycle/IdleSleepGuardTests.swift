import Foundation
import Testing

@testable import Plumage

@Suite("IdleSleepGuard")
@MainActor
struct IdleSleepGuardTests {
    @Test("acquires exactly one assertion when it should hold")
    func acquiresOnce() {
        let asserter = FakeAsserter()
        let sut = IdleSleepGuard(asserter: asserter, reason: "session running")

        sut.update(shouldHold: true)

        #expect(asserter.beginCount == 1)
        #expect(asserter.endCount == 0)
        #expect(asserter.heldCount == 1)
        #expect(sut.isHolding)
        #expect(asserter.lastReason == "session running")
    }

    @Test("repeated hold never double-acquires")
    func idempotentHold() {
        let asserter = FakeAsserter()
        let sut = IdleSleepGuard(asserter: asserter)

        sut.update(shouldHold: true)
        sut.update(shouldHold: true)
        sut.update(shouldHold: true)

        #expect(asserter.beginCount == 1)
        #expect(asserter.heldCount == 1)
        #expect(sut.isHolding)
    }

    @Test("releases the held assertion when it should no longer hold")
    func releasesWhenHeld() {
        let asserter = FakeAsserter()
        let sut = IdleSleepGuard(asserter: asserter)

        sut.update(shouldHold: true)
        sut.update(shouldHold: false)

        #expect(asserter.endCount == 1)
        #expect(asserter.heldCount == 0)
        #expect(!sut.isHolding)
    }

    @Test("release when nothing is held is a no-op")
    func noReleaseWhenNone() {
        let asserter = FakeAsserter()
        let sut = IdleSleepGuard(asserter: asserter)

        sut.update(shouldHold: false)
        sut.update(shouldHold: false)

        #expect(asserter.beginCount == 0)
        #expect(asserter.endCount == 0)
        #expect(!sut.isHolding)
    }

    @Test("re-acquires after a release across start/stop churn")
    func reacquiresAfterRelease() {
        let asserter = FakeAsserter()
        let sut = IdleSleepGuard(asserter: asserter)

        sut.update(shouldHold: true)
        sut.update(shouldHold: false)
        sut.update(shouldHold: true)

        #expect(asserter.beginCount == 2)
        #expect(asserter.endCount == 1)
        #expect(asserter.heldCount == 1)
        #expect(sut.isHolding)
    }
}

private final class FakeAsserter: IdleSleepAsserting {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var lastReason: String?
    var heldCount: Int { beginCount - endCount }

    func begin(reason: String) -> any NSObjectProtocol {
        beginCount += 1
        lastReason = reason
        return NSObject()
    }

    func end(_ token: any NSObjectProtocol) {
        endCount += 1
    }
}
