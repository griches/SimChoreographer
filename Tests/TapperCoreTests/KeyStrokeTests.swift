import XCTest
import CoreGraphics
@testable import TapperCore
@testable import Tapper

final class KeyStrokeTests: XCTestCase {
    func testNamedKeysAndAliases() throws {
        for (name, code) in [("return", 36), ("enter", 36), ("TAB", 48), ("space", 49),
                             ("backspace", 51), ("delete", 51), ("escape", 53), ("esc", 53),
                             ("forwarddelete", 117), ("left", 123), ("right", 124), ("down", 125), ("up", 126)] {
            let stroke = try KeyStroke(name)
            XCTAssertEqual(stroke.keyCode, UInt16(code))
            XCTAssertEqual(stroke.modifiers, 0)
        }
        XCTAssertEqual(try KeyStroke("A"), try KeyStroke("a"))
        XCTAssertEqual(try KeyStroke("cmd+a"), try KeyStroke("command+a"))
        XCTAssertEqual(try KeyStroke("ctrl+alt+a"), try KeyStroke("control+option+a"))
    }
    func testShortcutProducesPairedMarkedEvents() throws {
        let stroke = try KeyStroke(" CMD + Shift + a ")
        XCTAssertEqual(stroke.modifiers, CGEventFlags([.maskCommand, .maskShift]).rawValue)
        let events = try Keyboard.events(keyCode: stroke.keyCode, modifiers: stroke.modifiers)
        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [56, 55, 0, 0, 55, 56])
        XCTAssertEqual(events[2].type, .keyDown)
        XCTAssertEqual(events[3].type, .keyUp)
        XCTAssertEqual(events[0].flags, .maskShift)
        XCTAssertEqual(events[4].flags, .maskShift)
        XCTAssertEqual(events.last?.flags, [])
        XCTAssertTrue(events.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == Keyboard.eventMarker })
    }
    func testMalformedAndReservedShortcutsRejected() {
        for input in ["", " ", "cmd", "cmd+", "+a", "cmd++a", "banana+a", "ctrl+ctrl+a",
                      "cmd+command+a", "hello", "cmd+shift+escape", "ctrl+shift+cmd+esc"] {
            XCTAssertThrowsError(try KeyStroke(input), input)
        }
    }
    func testCommandRoundTripAndBackwardCompatibility() throws {
        let command = Command(action: "key", key: "shift+tab", windowTitle: "iPhone")
        let encoded = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(Command.self, from: encoded)
        XCTAssertEqual(decoded.key, "shift+tab")
        XCTAssertEqual(decoded.windowTitle, "iPhone")
        XCTAssertEqual(decoded.action, "key")
        XCTAssertNil(decoded.recording)
        let oldJSON = #"{"id":"D881870B-CA60-4997-BA8D-D850520BCA32","action":"status","delay":0,"expires":123456789}"#
        let old = try JSONDecoder().decode(Command.self, from: Data(oldJSON.utf8))
        XCTAssertNil(old.key)
        XCTAssertNil(old.windowTitle)
    }
    func testBusyControllerRejectsDirectKeysBeforeDelivery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = Controller(store: try Store(root: directory))
        controller.recording = true
        XCTAssertThrowsError(try controller.sendKey("return") { _ in XCTFail("No key should be delivered") })
        controller.recording = false; controller.playing = true
        XCTAssertThrowsError(try controller.sendKey("return") { _ in XCTFail("No key should be delivered") })
        XCTAssertTrue(controller.recordings.isEmpty)
    }
}
