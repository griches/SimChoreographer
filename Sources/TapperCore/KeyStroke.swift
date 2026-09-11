import Foundation
import CoreGraphics

/// Named physical keys use the macOS virtual-key positions of a US keyboard.
/// The active Simulator/Mac keyboard layout determines the resulting character.
public struct KeyStroke: Equatable {
    public let keyCode: UInt16
    public let modifiers: UInt64

    public init(_ shortcut: String) throws {
        let parts = shortcut.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let key = parts.last, !key.isEmpty, !parts.contains("") else {
            throw TapperError("Use a key such as return, or a shortcut such as cmd+shift+a")
        }
        let modifierNames: [String: CGEventFlags] = [
            "cmd": .maskCommand, "command": .maskCommand,
            "ctrl": .maskControl, "control": .maskControl,
            "alt": .maskAlternate, "option": .maskAlternate,
            "shift": .maskShift, "fn": .maskSecondaryFn
        ]
        var flags = CGEventFlags()
        for name in parts.dropLast() {
            guard let flag = modifierNames[name], !flags.contains(flag) else {
                throw TapperError("Unknown or repeated modifier '\(name)'")
            }
            flags.insert(flag)
        }
        let keys: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
            "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
            "equals": 24, "minus": 27, "rightbracket": 30, "leftbracket": 33, "quote": 39,
            "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "period": 47, "grave": 50,
            "return": 36, "enter": 36, "tab": 48, "space": 49, "backspace": 51, "delete": 51,
            "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115, "end": 119,
            "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
        ]
        guard let code = keys[key] else { throw TapperError("Unknown key '\(key)'; use --help for supported names") }
        guard !Keyboard.isStopShortcut(keyCode: code, modifiers: flags.rawValue) else {
            throw TapperError("Command–Shift–Escape is reserved for stopping; use simchoreographerctl stop")
        }
        keyCode = code; modifiers = flags.rawValue
    }
}
