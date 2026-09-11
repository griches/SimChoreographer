import Foundation

public enum MousePhase: String, Codable { case down, drag, up }

/// A best-effort snapshot of the accessibility element at mouse-down.
/// Direct matches can relocate ordinary taps during playback.
public struct ElementSnapshot: Codable, Equatable {
    public var label: String?
    public var identifier: String?
    public var role: String?
    public var ancestorDepth: Int
    public init(label: String? = nil, identifier: String? = nil, role: String? = nil, ancestorDepth: Int = 0) {
        func clean(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return String(text.prefix(512))
        }
        self.label = clean(label); self.identifier = clean(identifier); self.role = clean(role)
        self.ancestorDepth = ancestorDepth
    }
    public var hasName: Bool { label != nil || identifier != nil }
    public var title: String { label ?? identifier ?? "Unlabelled element" }
}

public struct Tap: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var delay: Double
    // Optional fields keep the original tap-only JSON format readable.
    public var keyCode: UInt16?
    public var modifiers: UInt64?
    public var mousePhase: MousePhase?
    public var element: ElementSnapshot?
    public init(x: Double, y: Double, phase: MousePhase, delay: Double) {
        self.x = x; self.y = y; self.mousePhase = phase; self.delay = delay
    }
    public init(keyCode: UInt16, modifiers: UInt64 = 0, delay: Double) {
        x = 0; y = 0; self.delay = delay; self.keyCode = keyCode; self.modifiers = modifiers
    }
    public init(x: Double, y: Double, delay: Double) { self.x = x; self.y = y; self.delay = delay }
}
public struct Recording: Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var windowTitle: String
    public var width: Double
    public var height: Double
    public var taps: [Tap]
    public init(name: String, windowTitle: String, width: Double, height: Double) {
        id = UUID(); self.name = name; self.windowTitle = windowTitle
        self.width = width; self.height = height; taps = []
    }
    public var summary: String {
        var keys = 0, clicks = 0, gestures = 0
        var press: Tap?
        var duration = 0.0
        var moved = false
        for input in taps {
            if press != nil { duration += input.delay }
            if input.keyCode != nil { keys += 1; continue }
            switch input.mousePhase {
            case .down:
                press = input; duration = 0; moved = false
            case .drag, .up:
                guard let start = press else { continue }
                // Ignore small pointer jitter, but retain any substantial movement
                // even if the pointer returns to its starting point.
                moved = moved || hypot(input.x - start.x, input.y - start.y) >= 5
                if input.mousePhase == .up {
                    if duration < 0.6 && !moved { clicks += 1 } else { gestures += 1 }
                    press = nil
                }
            case nil:
                clicks += 1
            }
        }
        return gestures == 0 ? "\(clicks) taps · \(keys) keys" : "\(clicks) taps · \(gestures) gestures · \(keys) keys"
    }

    /// Discard a gesture interrupted before release, including input inside it.
    /// Earlier completed input remains safe to replay.
    public mutating func discardIncompleteGesture() {
        var start: Int?
        for (index, step) in taps.enumerated() {
            if step.mousePhase == .down { start = index }
            if step.mousePhase == .up { start = nil }
        }
        if let start { taps.removeSubrange(start...) }
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              width.isFinite, height.isFinite, width > 0, height > 0,
              !taps.isEmpty, taps.count <= 10000 else { throw TapperError("Invalid or empty recording") }
        var mouseHeld = false
        for tap in taps {
            guard tap.delay.isFinite, tap.delay >= 0, tap.delay <= 3600 else { throw TapperError("Invalid event timing") }
            if let code = tap.keyCode {
                guard tap.mousePhase == nil, code <= 127, (tap.modifiers ?? 0) & ~Keyboard.allowedModifiers == 0,
                      !Keyboard.isStopShortcut(keyCode: code, modifiers: tap.modifiers ?? 0) else { throw TapperError("Invalid key or reserved stop shortcut") }
                continue
            }
            switch tap.mousePhase {
            case .down:
                guard !mouseHeld else { throw TapperError("Mouse pressed twice without release") }
                mouseHeld = true
            case .drag:
                guard mouseHeld else { throw TapperError("Drag without mouse press") }
            case .up:
                guard mouseHeld else { throw TapperError("Mouse release without press") }
                mouseHeld = false
            case nil:
                guard !mouseHeld else { throw TapperError("Legacy click inside a held gesture") }
            }
            guard tap.modifiers == nil, tap.x.isFinite, tap.y.isFinite, tap.delay.isFinite,
                  tap.x >= 0, tap.x < width, tap.y >= 0, tap.y < height,
                  tap.delay >= 0, tap.delay <= 3600 else { throw TapperError("Invalid tap coordinates or timing") }
        }
        guard !mouseHeld else { throw TapperError("Gesture is missing mouse release") }
    }
}
public struct TapperError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct Command: Codable {
    public var id: UUID
    public var action: String
    public var recording: String?
    public var delay: Double
    public var strictElements: Bool?
    public var expires: Date
    public init(action: String, recording: String? = nil, delay: Double = 0, strictElements: Bool = false) {
        self.strictElements = strictElements
        id = UUID(); self.action = action; self.recording = recording; self.delay = delay
        expires = Date().addingTimeInterval(10)
    }
}
public struct Reply: Codable {
    public var ok: Bool
    public var message: String
    public var recordings: [Recording]?
    public init(ok: Bool, message: String, recordings: [Recording]? = nil) {
        self.ok = ok; self.message = message; self.recordings = recordings
    }
}
public struct Store {
    public let root: URL
    public var recordingsURL: URL { root.appendingPathComponent("recordings.json") }
    public var inbox: URL { root.appendingPathComponent("commands") }
    public var outbox: URL { root.appendingPathComponent("replies") }
    public init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tapper")
        for directory in [self.root, inbox, outbox] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }
    public func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
    public func write<T: Encodable>(_ value: T, at url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func load() throws -> [Recording] {
        guard FileManager.default.fileExists(atPath: recordingsURL.path) else { return [] }
        return try read([Recording].self, at: recordingsURL)
    }
}
