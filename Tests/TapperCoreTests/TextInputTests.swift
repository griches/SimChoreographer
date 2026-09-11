import XCTest
import CoreGraphics
@testable import TapperCore
@testable import Tapper

final class TextInputTests: XCTestCase {
    func testUnicodeSurvivesChunkingAndEventConstruction() throws {
        let text = "  Hello, Café! 👩🏽‍💻 e\u{301}\n日本語\t" + String(repeating: "🙂", count: 25)
        let chunks = try TextInput.chunks(text)
        XCTAssertEqual(chunks.flatMap { $0 }, Array(text.utf16))
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 20 })
        for chunk in chunks {
            XCTAssertFalse((0xDC00...0xDFFF).contains(chunk.first!))
            XCTAssertFalse((0xD800...0xDBFF).contains(chunk.last!))
            let events = try TextInput.events(chunk)
            XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
            for event in events {
                var length = 0
                var result = [UInt16](repeating: 0, count: 20)
                event.keyboardGetUnicodeString(maxStringLength: result.count, actualStringLength: &length, unicodeString: &result)
                XCTAssertEqual(Array(result.prefix(length)), chunk)
                XCTAssertEqual(event.flags, [])
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), Keyboard.eventMarker)
            }
        }
    }
    func testSurrogatePairAtChunkBoundaryAndLengthLimit() throws {
        let text = String(repeating: "a", count: 19) + "🙂b"
        let chunks = try TextInput.chunks(text)
        XCTAssertEqual(chunks.map(\.count), [19, 3])
        XCTAssertEqual(try TextInput.chunks(String(repeating: "a", count: 10_000)).count, 500)
        XCTAssertThrowsError(try TextInput.chunks(String(repeating: "a", count: 10_001)))
        XCTAssertThrowsError(try TextInput.chunks(String(repeating: "🙂", count: 5_001)))
        XCTAssertThrowsError(try TextInput.chunks(""))
        XCTAssertThrowsError(try TextInput.chunks("a\0b"))
        XCTAssertEqual(try TextInput.chunks(" ").flatMap { $0 }, [32])
    }
    func testCommandRoundTripAndOldCommands() throws {
        let text = "Mixed CASE, quotes \"hello\", café 🙂"
        let original = Command(action: "text", text: text, windowTitle: "iPhone")
        let decoded = try JSONDecoder().decode(Command.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.text, text)
        XCTAssertEqual(decoded.windowTitle, "iPhone")
        XCTAssertNil(decoded.key)
        let json = #"{"id":"D881870B-CA60-4997-BA8D-D850520BCA32","action":"key","key":"j","delay":0,"expires":123456789}"#
        let old = try JSONDecoder().decode(Command.self, from: Data(json.utf8))
        XCTAssertNil(old.text)
        XCTAssertEqual(old.key, "j")
    }
    func testBusyOrInvalidTextCannotStartDeliveryOrSaveARecording() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(root: directory)
        let controller = Controller(store: store)
        controller.recording = true
        XCTAssertThrowsError(try controller.sendText("Hello") { _ in XCTFail("Unexpected delivery") })
        controller.recording = false; controller.playing = true
        XCTAssertThrowsError(try controller.sendText("Hello") { _ in XCTFail("Unexpected delivery") })
        controller.playing = false
        XCTAssertThrowsError(try controller.sendText("") { _ in XCTFail("Unexpected delivery") })
        XCTAssertTrue(controller.recordings.isEmpty)
        XCTAssertTrue(try store.load().isEmpty)
    }
}
