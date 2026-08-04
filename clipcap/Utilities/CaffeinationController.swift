import Foundation
import IOKit.pwr_mgt

enum CaffeinationPreset: CaseIterable, Equatable {
    case tenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case eightHours
    case twelveHours

    var duration: TimeInterval {
        switch self {
        case .tenMinutes: return 10 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .eightHours: return 8 * 60 * 60
        case .twelveHours: return 12 * 60 * 60
        }
    }
}

struct CaffeinationSession: Equatable {
    let startedAt: Date
    let endDate: Date?
    let preset: CaffeinationPreset?

    var isIndefinite: Bool { endDate == nil }
}

enum CaffeinationState: Equatable {
    case inactive
    case active(CaffeinationSession)
}

protocol PowerAssertionManaging: AnyObject {
    func acquire(timeout: TimeInterval?) -> Bool
    func release()
}

/// Owns only the assertions created by clipcap. This gives the same default
/// display, system, and disk idle prevention as Coffee's `caffeinate -dmi`
/// without launching a detached process or terminating another app's
/// `caffeinate` process.
final class IOKitPowerAssertionManager: PowerAssertionManaging {
    private static let assertionTypes: [String] = [
        kIOPMAssertPreventUserIdleDisplaySleep,
        kIOPMAssertPreventUserIdleSystemSleep,
        kIOPMAssertPreventDiskIdle,
    ]

    private var assertionIDs: [IOPMAssertionID] = []

    func acquire(timeout: TimeInterval?) -> Bool {
        release()

        let assertionTimeout = max(0, timeout ?? 0)
        let timeoutAction: CFString? = assertionTimeout > 0
            ? kIOPMAssertionTimeoutActionTurnOff as CFString
            : nil

        for assertionType in Self.assertionTypes {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithDescription(
                assertionType as CFString,
                "clipcap Caffeinate" as CFString,
                "The user asked clipcap to keep this Mac awake" as CFString,
                nil,
                nil,
                assertionTimeout,
                timeoutAction,
                &assertionID
            )

            guard result == kIOReturnSuccess else {
                release()
                return false
            }
            assertionIDs.append(assertionID)
        }

        return true
    }

    func release() {
        assertionIDs.forEach { _ = IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }

    deinit {
        release()
    }
}

final class CaffeinationController {
    static let shared = CaffeinationController()

    private(set) var state: CaffeinationState = .inactive

    private let powerAssertions: PowerAssertionManaging
    private let now: () -> Date
    private var expirationTimer: Timer?

    init(
        powerAssertions: PowerAssertionManaging = IOKitPowerAssertionManager(),
        now: @escaping () -> Date = Date.init
    ) {
        self.powerAssertions = powerAssertions
        self.now = now
    }

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var activeSession: CaffeinationSession? {
        guard case .active(let session) = state else { return nil }
        return session
    }

    var activePreset: CaffeinationPreset? { activeSession?.preset }
    var activeEndDate: Date? { activeSession?.endDate }
    var isIndefinite: Bool { activeSession?.isIndefinite == true }

    @discardableResult
    func startIndefinitely() -> Bool {
        let session = CaffeinationSession(startedAt: now(), endDate: nil, preset: nil)
        return activate(session: session, timeout: nil)
    }

    @discardableResult
    func start(preset: CaffeinationPreset) -> Bool {
        let startedAt = now()
        let session = CaffeinationSession(
            startedAt: startedAt,
            endDate: startedAt.addingTimeInterval(preset.duration),
            preset: preset
        )
        return activate(session: session, timeout: preset.duration)
    }

    @discardableResult
    func start(until endDate: Date) -> Bool {
        let startedAt = now()
        let duration = endDate.timeIntervalSince(startedAt)
        guard duration > 0 else { return false }
        let session = CaffeinationSession(startedAt: startedAt, endDate: endDate, preset: nil)
        return activate(session: session, timeout: duration)
    }

    func remainingTime(at date: Date = Date()) -> TimeInterval? {
        guard let endDate = activeEndDate else { return nil }
        return max(0, endDate.timeIntervalSince(date))
    }

    func stop() {
        let wasActive = isActive
        expirationTimer?.invalidate()
        expirationTimer = nil
        powerAssertions.release()
        state = .inactive
        if wasActive { notifyStateChanged() }
    }

    private func activate(session: CaffeinationSession, timeout: TimeInterval?) -> Bool {
        let wasActive = isActive
        expirationTimer?.invalidate()
        expirationTimer = nil
        powerAssertions.release()
        state = .inactive

        guard powerAssertions.acquire(timeout: timeout) else {
            if wasActive { notifyStateChanged() }
            return false
        }

        state = .active(session)
        scheduleExpiration(for: session)
        notifyStateChanged()
        return true
    }

    private func scheduleExpiration(for session: CaffeinationSession) {
        guard let endDate = session.endDate else { return }
        let delay = endDate.timeIntervalSince(now())
        guard delay > 0 else {
            stop()
            return
        }

        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.expireSession(endingAt: endDate)
        }
        timer.tolerance = min(1, delay * 0.01)
        RunLoop.main.add(timer, forMode: .common)
        expirationTimer = timer
    }

    private func expireSession(endingAt expectedEndDate: Date) {
        guard activeEndDate == expectedEndDate else { return }
        stop()
    }

    private func notifyStateChanged() {
        NotificationCenter.default.post(name: .caffeinationStateDidChange, object: self)
    }

    deinit {
        expirationTimer?.invalidate()
        powerAssertions.release()
    }
}
