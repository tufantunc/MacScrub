import CoreGraphics
import AppKit

@MainActor
final class EventBlocker: EventBlockerProtocol {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isBlocking = false
    var onFlagsChanged: ((CGEventFlags) -> Void)?
    var onKeyActivity: (() -> Void)?

    func start() -> Bool {
        guard !isBlocking else { return true }

        // Built via an explicitly-typed reduce: the equivalent single OR-chain
        // expression trips the Swift type-checker's "too complex" timeout in
        // optimized (Release/archive) builds.
        let blockedEventTypes: [CGEventType] = [
            .keyDown, .keyUp,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .leftMouseDragged, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp,
            .scrollWheel, .flagsChanged,
        ]
        let eventMask: CGEventMask = blockedEventTypes.reduce(into: CGEventMask(0)) { mask, type in
            mask |= CGEventMask(1) << CGEventMask(type.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let runLoopSource else { return false }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isBlocking = true
        return true
    }

    func stop() {
        guard isBlocking, let eventTap, let runLoopSource else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        self.eventTap = nil
        self.runLoopSource = nil
        isBlocking = false
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }

    let blocker = Unmanaged<EventBlocker>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            if let tap = blocker.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }

    if type == .flagsChanged {
        let flags = event.flags
        Task { @MainActor in
            blocker.onFlagsChanged?(flags)
            blocker.onKeyActivity?()
        }
        return Unmanaged.passRetained(event)
    }

    if type == .keyDown || type == .keyUp {
        Task { @MainActor in
            blocker.onKeyActivity?()
        }
        return nil
    }

    let mouseLocation = NSEvent.mouseLocation
    let screenHeight = NSScreen.screens.first?.frame.height ?? 0
    let statusBarHeight: CGFloat = 25
    let adjustedY = screenHeight - mouseLocation.y
    if adjustedY <= statusBarHeight && (type == .leftMouseDown || type == .rightMouseDown || type == .leftMouseUp || type == .rightMouseUp) {
        return Unmanaged.passRetained(event)
    }

    return nil
}
