import XCTest
@testable import TapperCore

final class AccessibilityTests: XCTestCase {
    func testOldEventsHaveNoMetadata() throws {
        let json = #"[{"x":12,"y":34,"delay":0},{"x":12,"y":34,"delay":0.2,"mousePhase":"down"},{"x":12,"y":34,"delay":0.1,"mousePhase":"up"}]"#
        let events = try JSONDecoder().decode([Tap].self, from: Data(json.utf8))
        XCTAssertTrue(events.allSatisfy { $0.element == nil })
    }

    func testMetadataPersistsWithoutChangingPlaybackTimeline() throws {
        var recording = Recording(name: "Checkout", windowTitle: "iPhone", width: 400, height: 800)
        recording.taps = [Tap(x: 20, y: 40, phase: .down, delay: 0),
                          Tap(keyCode: 36, delay: 0.1),
                          Tap(x: 20, y: 40, phase: .up, delay: 0.1)]
        let originalSummary = recording.summary
        recording.taps[0].element = ElementSnapshot(label: "Continue", identifier: "checkout_continue", role: "AXButton", ancestorDepth: 1)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store(root: directory)
        try store.write([recording], at: store.recordingsURL)
        let loaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(loaded.taps, recording.taps)
        XCTAssertEqual(loaded.summary, originalSummary)
        try loaded.validate()
        // The existing agent reply carries the same metadata without a separate schema.
        let data = try JSONEncoder().encode(Reply(ok: true, message: "Saved sequences", recordings: [loaded]))
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        XCTAssertEqual(reply.recordings?.first?.taps[0].element?.identifier, "checkout_continue")
        XCTAssertEqual(reply.recordings?.first?.taps[0].element?.ancestorDepth, 1)
    }

    func testEmptyAndOversizedAttributes() {
        let unnamed = ElementSnapshot(label: " \n", identifier: "", role: "AXGroup")
        XCTAssertFalse(unnamed.hasName)
        XCTAssertEqual(unnamed.title, "Unlabelled element")
        XCTAssertEqual(ElementSnapshot(identifier: " go ").title, "go")
        XCTAssertEqual(ElementSnapshot(label: String(repeating: "a", count: 1000)).label?.count, 512)
    }
}
