import CoreGraphics

@MainActor
protocol EventBlockerProtocol {
    var isBlocking: Bool { get }
    var onFlagsChanged: ((CGEventFlags) -> Void)? { get set }
    func start() -> Bool
    func stop()
}
