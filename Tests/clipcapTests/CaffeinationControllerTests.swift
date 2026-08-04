import Foundation
import XCTest
@testable import clipcap

final class CaffeinationControllerTests: XCTestCase {
    func testNativeAssertionsAcquireWithoutSpecialPrivileges() {
        let assertions = IOKitPowerAssertionManager()
        XCTAssertTrue(assertions.acquire(timeout: 1))
        assertions.release()
    }

    func testPresetsMatchCoffeeMenuDurationsAndOrder() {
        let actual = CaffeinationPreset.allCases.map(\.duration)
        let expected: [TimeInterval] = [600, 1_800, 3_600, 7_200, 14_400, 28_800, 43_200]
        XCTAssertEqual(actual, expected)
    }

    func testIndefiniteSessionAcquiresUntilExplicitStop() {
        let assertions = FakePowerAssertions()
        let now = Date(timeIntervalSince1970: 1_000)
        let controller = CaffeinationController(powerAssertions: assertions, now: { now })

        XCTAssertTrue(controller.startIndefinitely())
        XCTAssertEqual(assertions.acquiredTimeouts.count, 1)
        XCTAssertNil(assertions.acquiredTimeouts[0])
        XCTAssertTrue(controller.isActive)
        XCTAssertTrue(controller.isIndefinite)

        controller.stop()

        XCTAssertEqual(controller.state, .inactive)
        XCTAssertEqual(assertions.releasedSessionCount, 1)
    }

    func testPresetSessionTracksEndDateAndTimeout() {
        let assertions = FakePowerAssertions()
        let now = Date(timeIntervalSince1970: 2_000)
        let controller = CaffeinationController(powerAssertions: assertions, now: { now })

        XCTAssertTrue(controller.start(preset: .thirtyMinutes))

        XCTAssertEqual(assertions.acquiredTimeouts, [30 * 60])
        XCTAssertEqual(controller.activePreset, .thirtyMinutes)
        XCTAssertEqual(controller.activeEndDate, now.addingTimeInterval(30 * 60))
        XCTAssertEqual(controller.remainingTime(at: now.addingTimeInterval(2)), 30 * 60 - 2)
    }

    func testStartingAnotherSessionReleasesOnlyThePreviousClipcapSession() {
        let assertions = FakePowerAssertions()
        let now = Date(timeIntervalSince1970: 3_000)
        let controller = CaffeinationController(powerAssertions: assertions, now: { now })

        XCTAssertTrue(controller.startIndefinitely())
        XCTAssertTrue(controller.start(preset: .oneHour))

        XCTAssertEqual(assertions.releasedSessionCount, 1)
        XCTAssertEqual(assertions.acquiredTimeouts.count, 2)
        XCTAssertNil(assertions.acquiredTimeouts[0])
        XCTAssertEqual(assertions.acquiredTimeouts[1], 60 * 60)
        XCTAssertEqual(controller.activePreset, .oneHour)
    }

    func testPastUntilDateIsRejectedWithoutChangingAnActiveSession() {
        let assertions = FakePowerAssertions()
        let now = Date(timeIntervalSince1970: 4_000)
        let controller = CaffeinationController(powerAssertions: assertions, now: { now })
        XCTAssertTrue(controller.startIndefinitely())

        XCTAssertFalse(controller.start(until: now.addingTimeInterval(-1)))

        XCTAssertTrue(controller.isIndefinite)
        XCTAssertEqual(assertions.acquiredTimeouts.count, 1)
        XCTAssertEqual(assertions.releasedSessionCount, 0)
    }

    func testAssertionFailureLeavesControllerInactive() {
        let assertions = FakePowerAssertions()
        assertions.shouldAcquire = false
        let controller = CaffeinationController(powerAssertions: assertions)

        XCTAssertFalse(controller.startIndefinitely())
        XCTAssertEqual(controller.state, .inactive)
        XCTAssertFalse(assertions.isHeld)
    }

    func testUntilSessionExpiresAndReleasesAssertions() {
        let assertions = FakePowerAssertions()
        let controller = CaffeinationController(powerAssertions: assertions)
        XCTAssertTrue(controller.start(until: Date().addingTimeInterval(0.05)))

        let expired = expectation(description: "Timed caffeination expires")
        let observer = NotificationCenter.default.addObserver(
            forName: .caffeinationStateDidChange,
            object: controller,
            queue: .main
        ) { _ in
            if controller.state == .inactive { expired.fulfill() }
        }

        wait(for: [expired], timeout: 1)
        NotificationCenter.default.removeObserver(observer)
        XCTAssertEqual(assertions.releasedSessionCount, 1)
    }
}

private final class FakePowerAssertions: PowerAssertionManaging {
    var shouldAcquire = true
    private(set) var acquiredTimeouts: [TimeInterval?] = []
    private(set) var releasedSessionCount = 0
    private(set) var isHeld = false

    func acquire(timeout: TimeInterval?) -> Bool {
        acquiredTimeouts.append(timeout)
        isHeld = shouldAcquire
        return shouldAcquire
    }

    func release() {
        guard isHeld else { return }
        releasedSessionCount += 1
        isHeld = false
    }
}
