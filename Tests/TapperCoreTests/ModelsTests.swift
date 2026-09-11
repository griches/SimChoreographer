import XCTest
@testable import TapperCore

final class ModelsTests: XCTestCase {
    func valid() -> Recording {
        var recording = Recording(name: "Login", windowTitle: "iPhone", width: 400, height: 800)
        recording.taps = [Tap(x: 100, y: 200, delay: 0), Tap(x: 200, y: 300, delay: 1.2)]
        return recording
    }
    func testValidRecording() throws { try valid().validate() }
    func testRejectsUnsafeCoordinatesAndTiming() {
        for tap in [Tap(x: -1, y: 0, delay: 0), Tap(x: 400, y: 0, delay: 0),
                    Tap(x: 0, y: 800, delay: 0), Tap(x: .infinity, y: 0, delay: 0),
                    Tap(x: 0, y: 0, delay: -1), Tap(x: 0, y: 0, delay: .nan),
                    Tap(x: 0, y: 0, delay: 3601)] {
            var recording = valid(); recording.taps = [tap]
            XCTAssertThrowsError(try recording.validate())
        }
    }
    func testRejectsEmptyRecording() {
        var recording = valid(); recording.taps = []
        XCTAssertThrowsError(try recording.validate())
    }
    func testStorageRoundTripAndPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(root: directory)
        XCTAssertTrue(try store.load().isEmpty)
        let original = valid()
        try store.write([original], at: store.recordingsURL)
        let loaded = try store.load()
        XCTAssertEqual(loaded.first?.id, original.id)
        XCTAssertEqual(loaded.first?.taps, original.taps)
        let file = try FileManager.default.attributesOfItem(atPath: store.recordingsURL.path)
        let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
    func testCorruptStorageIsNotSilentlyDiscarded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(root: directory)
        try Data("broken".utf8).write(to: store.recordingsURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: store.recordingsURL), "broken")
    }
}
