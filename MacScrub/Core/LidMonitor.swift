import Foundation
import IOKit
import IOKit.pwr_mgt

private let kIOMessageSystemWillPowerOn: UInt32 = 0x04000320

@MainActor
protocol LidMonitorProtocol: AnyObject {
    var onLidOpen: (() -> Void)? { get set }
    func start()
    func stop()
}

@MainActor
final class LidMonitor: LidMonitorProtocol {
    var onLidOpen: (() -> Void)?
    private var rootPort: io_object_t = 0
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = 0

    func start() {
        guard notificationPort == nil else { return }
        rootPort = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard rootPort != 0 else { return }

        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOServiceAddInterestNotification(
            notificationPort,
            rootPort,
            kIOGeneralInterest,
            lidCallback,
            selfPtr,
            &notifier
        )
    }

    func stop() {
        if notifier != 0 {
            IOObjectRelease(notifier)
            notifier = 0
        }
        if let notificationPort {
            let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        if rootPort != 0 {
            IOObjectRelease(rootPort)
            rootPort = 0
        }
    }
}

private func lidCallback(
    refcon: UnsafeMutableRawPointer?,
    service: UInt32,
    messageType: UInt32,
    messageArgument: UnsafeMutableRawPointer?
) {
    guard messageType == kIOMessageSystemWillPowerOn else { return }
    guard let refcon else { return }
    let monitor = Unmanaged<LidMonitor>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        monitor.onLidOpen?()
    }
}
