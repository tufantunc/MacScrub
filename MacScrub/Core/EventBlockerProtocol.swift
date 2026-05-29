import CoreGraphics

@MainActor
protocol EventBlockerProtocol {
    var onFlagsChanged: ((CGEventFlags) -> Void)? { get set }
    var onKeyActivity: (() -> Void)? { get set }
    func start() -> Bool
    func stop()
}
