import Foundation

public enum ElementTargeting {
    /// A duplicate identifier is ambiguous; never rescue it with a weaker label match.
    public static func match(_ recorded: ElementSnapshot?, candidates: [ElementSnapshot], complete: Bool) throws -> Int {
        guard complete else { throw TapperError("Accessibility search was incomplete") }
        guard let recorded, recorded.ancestorDepth == 0, recorded.hasName else {
            throw TapperError("No direct accessibility target was recorded")
        }
        // Snapshots cap attributes at 512 characters. Never use a potentially
        // truncated name as though it were an exact locator.
        guard (recorded.identifier?.count ?? 0) < 512, (recorded.label?.count ?? 0) < 512 else {
            throw TapperError("Recorded accessibility name may be truncated")
        }
        if let identifier = recorded.identifier {
            let matches = candidates.indices.filter { candidates[$0].identifier == identifier }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { throw TapperError("Accessibility identifier is ambiguous") }
        }
        if let label = recorded.label, let role = recorded.role {
            let matches = candidates.indices.filter { candidates[$0].label == label && candidates[$0].role == role }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 { throw TapperError("Accessibility label and type are ambiguous") }
        }
        throw TapperError("Accessibility target was not found")
    }

    /// Inclusive start/end indices for short stationary clicks. Keys within a hold
    /// keep the original path, since they may change the meaning of that gesture.
    public static func ordinaryTaps(_ events: [Tap]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var start: Int?
        var duration = 0.0
        var moved = false
        for (index, event) in events.enumerated() {
            if start != nil { duration += event.delay }
            if event.keyCode != nil { if start != nil { moved = true }; continue }
            switch event.mousePhase {
            case .down: start = index; duration = 0; moved = false
            case .drag, .up:
                guard let first = start else { continue }
                moved = moved || hypot(event.x - events[first].x, event.y - events[first].y) >= 5
                if event.mousePhase == .up {
                    if duration < 0.6 && !moved { result[first] = index }
                    start = nil
                }
            case nil: result[index] = index
            }
        }
        return result
    }
}
