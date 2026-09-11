import XCTest
import CoreGraphics
@testable import TapperCore

final class KeyboardTests: XCTestCase {
    func testLegacyTapJSONStillLoads() throws {
        let json = """
        {"id":"D881870B-CA60-4997-BA8D-D850520BCA32","name":"Old","windowTitle":"iPhone","width":400,"height":800,"taps":[{"x":50,"y":60,"delay":0}]}
        """
        let recording = try JSONDecoder().decode(Recording.self, from: Data(json.utf8))
        try recording.validate()
        XCTAssertNil(recording.taps.first?.keyCode)
        XCTAssertEqual(recording.summary, "1 taps · 0 keys")
    }
    func testMixedInputRoundTripPreservesOrderTimingAndModifiers() throws {
        var recording = Recording(name: "Mixed", windowTitle: "iPhone", width: 400, height: 800)
        recording.taps = [Tap(x: 10, y: 20, delay: 0), Tap(keyCode: 0, modifiers: CGEventFlags.maskShift.rawValue, delay: 0.25), Tap(keyCode: 36, delay: 1)]
        let result = try JSONDecoder().decode(Recording.self, from: JSONEncoder().encode(recording))
        try result.validate()
        XCTAssertEqual(recording.taps, result.taps)
        XCTAssertEqual(result.summary, "1 taps · 2 keys")
    }
    func testKeyboardOnlyRecordingAndInvalidKeys() throws {
        var recording = Recording(name: "Keys", windowTitle: "iPhone", width: 400, height: 800)
        recording.taps = [Tap(keyCode: 36, delay: 0)]
        try recording.validate()
        for input in [Tap(keyCode: 128, delay: 0), Tap(keyCode: 0, modifiers: 1, delay: 0),
                      Tap(keyCode: 53, modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue, delay: 0)] {
            recording.taps = [input]
            XCTAssertThrowsError(try recording.validate())
        }
    }
    func testShortcutEventsReleaseModifiersAndAreMarked() throws {
        let flags = CGEventFlags([.maskCommand, .maskShift])
        let events = try Keyboard.events(keyCode: 0, modifiers: flags.rawValue)
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [56, 55, 0, 0, 55, 56])
        XCTAssertEqual(events[2].type, .keyDown)
        XCTAssertEqual(events[3].type, .keyUp)
        XCTAssertEqual(events[2].flags, flags)
        XCTAssertEqual(events.last?.flags, [])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == Keyboard.eventMarker })
    }
    func testPlainKeyIsPairedAndStopShortcutCannotBeSynthesized() throws {
        let events = try Keyboard.events(keyCode: 36, modifiers: 0)
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        XCTAssertThrowsError(try Keyboard.events(keyCode: 53, modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue))
    }
}
