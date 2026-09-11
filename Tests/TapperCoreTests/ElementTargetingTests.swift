import XCTest
@testable import TapperCore

final class ElementTargetingTests: XCTestCase {
    let target = ElementSnapshot(label: "Continue", identifier: "continue", role: "AXButton")
    func testIdentifierWinsOverLabelAndLabelIsFallback() throws {
        let candidates = [ElementSnapshot(label: "Continue", role: "AXButton"),
                          ElementSnapshot(label: "Next", identifier: "continue", role: "AXButton")]
        XCTAssertEqual(try ElementTargeting.match(target, candidates: candidates, complete: true), 1)
        XCTAssertEqual(try ElementTargeting.match(target, candidates: [candidates[0]], complete: true), 0)
    }
    func testAmbiguityAndIncompleteSearchNeverPickFirst() {
        XCTAssertThrowsError(try ElementTargeting.match(target, candidates: [target, target], complete: true))
        let unnamedID = ElementSnapshot(label: "Continue", role: "AXButton")
        XCTAssertThrowsError(try ElementTargeting.match(target, candidates: [unnamedID, unnamedID], complete: true))
        XCTAssertThrowsError(try ElementTargeting.match(target, candidates: [target], complete: false))
        XCTAssertThrowsError(try ElementTargeting.match(target, candidates: [], complete: true))
    }
    func testTypeRequiredForLabelAndEnclosingElementsExcluded() {
        XCTAssertThrowsError(try ElementTargeting.match(target, candidates: [ElementSnapshot(label: "Continue", role: "AXTextField")], complete: true))
        XCTAssertThrowsError(try ElementTargeting.match(nil, candidates: [target], complete: true))
        var enclosing = target; enclosing.ancestorDepth = 1
        XCTAssertThrowsError(try ElementTargeting.match(enclosing, candidates: [target], complete: true))
    }
    func testTruncatedNamesCannotBecomeLocators() {
        let truncated = ElementSnapshot(identifier: String(repeating: "a", count: 600))
        XCTAssertThrowsError(try ElementTargeting.match(truncated, candidates: [truncated], complete: true))
    }
    func testOnlyOrdinaryClicksAreRelocated() {
        let events = [Tap(x: 10, y: 10, phase: .down, delay: 0),
                      Tap(x: 11, y: 11, phase: .drag, delay: 0.1),
                      Tap(x: 10, y: 10, phase: .up, delay: 0.1),
                      Tap(x: 10, y: 10, phase: .down, delay: 0.2),
                      Tap(x: 10, y: 10, phase: .up, delay: 0.6),
                      Tap(x: 10, y: 10, phase: .down, delay: 0),
                      Tap(x: 30, y: 10, phase: .drag, delay: 0.1),
                      Tap(x: 10, y: 10, phase: .up, delay: 0.1),
                      Tap(x: 10, y: 10, phase: .down, delay: 0),
                      Tap(keyCode: 36, delay: 0),
                      Tap(x: 10, y: 10, phase: .up, delay: 0.1),
                      Tap(x: 10, y: 10, delay: 0)]
        XCTAssertEqual(ElementTargeting.ordinaryTaps(events), [0: 2, 11: 11])
    }
    func testOldCommandsDefaultToNonStrictAndStrictRoundTrips() throws {
        let command = Command(action: "run", recording: "Example", strictElements: true)
        let encoder = JSONEncoder()
        let data = try encoder.encode(command)
        XCTAssertEqual(try JSONDecoder().decode(Command.self, from: data).strictElements, true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "strictElements")
        let old = try JSONSerialization.data(withJSONObject: json)
        XCTAssertNil(try JSONDecoder().decode(Command.self, from: old).strictElements)
    }
}
