import Foundation
import CoreGraphics

public enum TextInput {
    public static let maximumUTF16Length = 10_000

    /// Keep each event small, and never split a UTF-16 surrogate pair.
    public static func chunks(_ text: String) throws -> [[UInt16]] {
        guard !text.isEmpty, text.utf16.count <= maximumUTF16Length else {
            throw TapperError("Text must contain 1–10,000 UTF-16 code units")
        }
        guard !text.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw TapperError("Text cannot contain a NUL character")
        }
        var chunks: [[UInt16]] = []
        var current: [UInt16] = []
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if current.count + units.count > 20 { chunks.append(current); current = [] }
            current.append(contentsOf: units)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Build the press and release before either is posted. This does not use
    /// the clipboard or map characters to physical keyboard positions.
    public static func events(_ units: [UInt16]) throws -> [CGEvent] {
        guard !units.isEmpty, units.count <= 20 else { throw TapperError("Invalid text event length") }
        let source = CGEventSource(stateID: .privateState)
        return try [true, false].map { down in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else {
                throw TapperError("Could not create text event")
            }
            event.flags = []
            units.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            event.setIntegerValueField(.eventSourceUserData, value: Keyboard.eventMarker)
            return event
        }
    }
}
