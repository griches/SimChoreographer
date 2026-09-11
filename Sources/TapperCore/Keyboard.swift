import CoreGraphics

public enum Keyboard {
    public static let eventMarker: Int64 = 0x544150504552
    public static let allowedModifiers: UInt64 = CGEventFlags([
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskAlphaShift, .maskSecondaryFn, .maskNumericPad
    ]).rawValue

    public static func isStopShortcut(keyCode: UInt16, modifiers: UInt64) -> Bool {
        keyCode == 53 && CGEventFlags(rawValue: modifiers).contains([.maskCommand, .maskShift])
    }

    // Event construction is separate from delivery so it can be tested without typing.
    public static func events(keyCode: UInt16, modifiers: UInt64) throws -> [CGEvent] {
        guard keyCode <= 127, modifiers & ~allowedModifiers == 0,
              !isStopShortcut(keyCode: keyCode, modifiers: modifiers) else { throw TapperError("Invalid key or reserved stop shortcut") }
        let source = CGEventSource(stateID: .privateState)
        let flags = CGEventFlags(rawValue: modifiers)
        let modifierKeys: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55), (.maskSecondaryFn, 63)]
        var result: [CGEvent] = []
        var active = flags.intersection([.maskAlphaShift, .maskNumericPad])
        func make(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) throws -> CGEvent {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { throw TapperError("Could not create keyboard event") }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            return event
        }
        let held = modifierKeys.filter { flags.contains($0.0) }
        for (flag, code) in held {
            active.insert(flag); result.append(try make(code, down: true, flags: active))
        }
        result.append(try make(keyCode, down: true, flags: flags))
        result.append(try make(keyCode, down: false, flags: flags))
        for (flag, code) in held.reversed() {
            active.remove(flag); result.append(try make(code, down: false, flags: active))
        }
        return result
    }
}
