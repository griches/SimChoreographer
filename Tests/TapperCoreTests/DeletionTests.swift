import XCTest
import TapperCore
@testable import Tapper

final class DeletionTests: XCTestCase {
    func testDeleteAndUndoPersistAndPreserveOrder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        let originals = ["First", "Second", "Third"].map { Recording(name: $0, windowTitle: "iPhone", width: 400, height: 800) }
        try store.write(originals, at: store.recordingsURL)
        let model = Controller(store: store)
        model.delete(originals[1].id)
        XCTAssertEqual(try store.load().map(\.name), ["First", "Third"])
        XCTAssertEqual(model.recordings.map(\.name), ["First", "Third"])
        model.undoDelete()
        XCTAssertEqual(try store.load().map(\.id), originals.map(\.id))
        XCTAssertNil(model.deletedRecording)
        model.recording = true
        model.delete(originals[0].id)
        XCTAssertEqual(try store.load().count, 3)
        model.recording = false; model.playing = true
        model.delete(originals[0].id)
        XCTAssertEqual(try store.load().count, 3)
    }
    func testFailedSaveKeepsRecordingInMemory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Store(root: root)
        let item = Recording(name: "Keep", windowTitle: "iPhone", width: 400, height: 800)
        try store.write([item], at: store.recordingsURL)
        let model = Controller(store: store)
        try FileManager.default.removeItem(at: store.recordingsURL)
        try FileManager.default.createDirectory(at: store.recordingsURL, withIntermediateDirectories: false)
        model.delete(item.id)
        XCTAssertEqual(model.recordings.map(\.id), [item.id])
        XCTAssertNil(model.deletedRecording)
    }
}
