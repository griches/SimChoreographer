import CoreGraphics

/// Holds a prebuilt release event for every posted press. Delivery is injectable
/// so cleanup can be verified without moving the actual pointer.
public final class MousePlayback {
    private let deliver: (CGEvent) -> Void
    private var releaseEvent: CGEvent?
    public private(set) var location: CGPoint?
    public var isHeld: Bool { releaseEvent != nil }
    private let source = CGEventSource(stateID: .privateState)

    public init(deliver: @escaping (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        self.deliver = deliver
    }
    deinit { release() }
    private func event(_ type: CGEventType, at point: CGPoint) throws -> CGEvent {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            throw TapperError("Could not create mouse event")
        }
        event.flags = []
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Keyboard.eventMarker)
        return event
    }
    public func send(_ phase: MousePhase?, at point: CGPoint) throws {
        switch phase {
        case .down:
            guard !isHeld else { throw TapperError("Mouse is already held") }
            let down = try event(.leftMouseDown, at: point)
            releaseEvent = try event(.leftMouseUp, at: point)
            location = point
            deliver(down)
        case .drag:
            guard isHeld else { throw TapperError("Drag without mouse press") }
            let drag = try event(.leftMouseDragged, at: point)
            if let location {
                drag.setIntegerValueField(.mouseEventDeltaX, value: Int64(point.x - location.x))
                drag.setIntegerValueField(.mouseEventDeltaY, value: Int64(point.y - location.y))
            }
            releaseEvent = try event(.leftMouseUp, at: point)
            location = point
            deliver(drag)
        case .up:
            guard isHeld else { throw TapperError("Mouse release without press") }
            releaseEvent = try event(.leftMouseUp, at: point)
            release()
        case nil:
            try send(.down, at: point)
            release()
        }
    }
    public func release() {
        guard let event = releaseEvent else { return }
        releaseEvent = nil; location = nil
        deliver(event)
    }
}
