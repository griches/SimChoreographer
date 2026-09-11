import XCTest
import CoreGraphics
@testable import TapperCore

final class GestureTests: XCTestCase {
    func recording(_ steps: [Tap]) -> Recording {
        var recording = Recording(name: "Gesture", windowTitle: "iPhone", width: 400, height: 800)
        recording.taps = steps
        return recording
    }
    func step(_ phase: MousePhase, delay: Double = 0) -> Tap {
        Tap(x: 100, y: 200, phase: phase, delay: delay)
    }
    func testHoldDragRoundTripWithInterleavedKeyboard() throws {
        let original = recording([step(.down), step(.drag, delay: 1.5), Tap(keyCode: 36, delay: 0.1), step(.drag, delay: 0.02), step(.up, delay: 0.2)])
        let decoded = try JSONDecoder().decode(Recording.self, from: JSONEncoder().encode(original))
        try decoded.validate()
        XCTAssertEqual(decoded.taps, original.taps)
        XCTAssertEqual(decoded.summary, "0 taps · 1 gestures · 1 keys")
        try recording([step(.down), step(.up, delay: 2)]).validate()
    }
    func testSummaryDistinguishesTapsHoldsAndDrags() {
        let inputs = [
            Tap(x: 10, y: 20, delay: 0), // Legacy tap.
            step(.down, delay: 5), step(.up, delay: 0.1), // Wait before press isn't a hold.
            step(.down), Tap(x: 102, y: 201, phase: .drag, delay: 0.05), step(.up, delay: 0.1), // Jitter.
            step(.down), step(.up, delay: 0.6), // Long press.
            step(.down), Tap(x: 150, y: 200, phase: .drag, delay: 0.05), step(.up, delay: 0.05), // Out and back.
            Tap(keyCode: 36, delay: 0)
        ]
        XCTAssertEqual(recording(inputs).summary, "3 taps · 2 gestures · 1 keys")
        XCTAssertEqual(recording([step(.down)]).summary, "0 taps · 0 keys")
    }
    func testSummaryIncludesInterleavedKeyDelayInHoldDuration() {
        let inputs = [step(.down), Tap(keyCode: 36, delay: 0.5), step(.up, delay: 0.2)]
        XCTAssertEqual(recording(inputs).summary, "0 taps · 1 gestures · 1 keys")
    }
    func testRejectsUnbalancedGestures() {
        for steps in [[step(.drag)], [step(.up)], [step(.down)], [step(.down), step(.down), step(.up)],
                      [step(.down), Tap(x: 10, y: 20, delay: 0), step(.up)]] {
            XCTAssertThrowsError(try recording(steps).validate())
        }
        var ambiguous = Tap(keyCode: 36, delay: 0)
        ambiguous.mousePhase = .down
        XCTAssertThrowsError(try recording([ambiguous]).validate())
    }
    func testDiscardInterruptedGesturePreservesCompletedInput() throws {
        let completed = [step(.down), step(.up, delay: 0.1), Tap(keyCode: 0, delay: 0.5)]
        var value = recording(completed + [step(.down), step(.drag, delay: 1), Tap(keyCode: 36, delay: 0)])
        value.discardIncompleteGesture()
        XCTAssertEqual(value.taps, completed)
        try value.validate()
        value.discardIncompleteGesture()
        XCTAssertEqual(value.taps, completed)
        var onlyIncomplete = recording([step(.down), step(.drag)])
        onlyIncomplete.discardIncompleteGesture()
        XCTAssertTrue(onlyIncomplete.taps.isEmpty)
    }
    func testPlaybackTypesCoordinatesAndEmergencyRelease() throws {
        var delivered: [CGEvent] = []
        let mouse = MousePlayback { delivered.append($0) }
        try mouse.send(.down, at: CGPoint(x: 100, y: 200))
        XCTAssertTrue(mouse.isHeld)
        try mouse.send(.drag, at: CGPoint(x: 150, y: 240))
        XCTAssertEqual(delivered.map(\.type), [.leftMouseDown, .leftMouseDragged])
        XCTAssertEqual(delivered[1].getIntegerValueField(.mouseEventDeltaX), 50)
        mouse.release() // Same cleanup used on Stop and playback failure.
        mouse.release()
        XCTAssertFalse(mouse.isHeld)
        XCTAssertEqual(delivered.map(\.type), [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(delivered.last?.location, CGPoint(x: 150, y: 240))
        XCTAssertTrue(delivered.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == Keyboard.eventMarker })
    }
    func testNormalReleaseAndLegacyClick() throws {
        var events: [CGEvent] = []
        let mouse = MousePlayback { events.append($0) }
        try mouse.send(nil, at: CGPoint(x: 10, y: 20))
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseUp])
        try mouse.send(.down, at: CGPoint(x: 10, y: 20))
        try mouse.send(.up, at: CGPoint(x: 30, y: 40))
        XCTAssertFalse(mouse.isHeld)
        XCTAssertEqual(events.last?.location, CGPoint(x: 30, y: 40))
        XCTAssertThrowsError(try mouse.send(.drag, at: .zero))
    }
    func testDeallocationReleasesHeldButton() throws {
        var events: [CGEventType] = []
        var mouse: MousePlayback? = MousePlayback { events.append($0.type) }
        try mouse?.send(.down, at: .zero)
        mouse = nil
        XCTAssertEqual(events, [.leftMouseDown, .leftMouseUp])
    }
}
