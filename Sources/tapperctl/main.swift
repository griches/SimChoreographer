import Foundation
import TapperCore

func output(_ reply: Reply) {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(reply) { print(String(decoding: data, as: UTF8.self)) }
}
do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args == ["--help"] {
        print("""
        simchoreographerctl list
        simchoreographerctl status
        simchoreographerctl run <name-or-uuid> [--delay seconds] [--timeout seconds] [--strict-elements]
        simchoreographerctl key <key-or-shortcut> [--window "exact Simulator title"] [--timeout seconds]
        simchoreographerctl stop

        Key examples: return, tab, escape, space, backspace, left, shift+tab, cmd+a.
        Keys: a-z, 0-9, f1-f12, up/down/left/right, home/end, pageup/pagedown,
        return/enter, tab, space, escape/esc, backspace/delete, forwarddelete,
        equals, minus, leftbracket, rightbracket, quote, semicolon, backslash,
        comma, slash, period, grave. Modifiers: cmd, ctrl, option/alt, shift, fn.
        Names are case-insensitive physical US key positions; use shift+a for Shift+A.
        With multiple Simulator windows, key requires --window.

        Open SimChoreographer first. Local agent control is enabled by default.
        run and key wait for completion; exit 0 = success, 1 = failure, 2 = timeout.
        Timeout does not cancel playback. Use simchoreographerctl stop to cancel.
        """)
        exit(0)
    }
    let action = args[0]
    guard ["list", "status", "run", "stop", "key"].contains(action) else { throw TapperError("Unknown command; use --help") }
    var key: String?; var windowTitle: String?
    var strictElements = false
    var name: String?; var delay = 0.0; var timeout = 300.0; var index = 1
    if action == "run" {
        guard args.count > 1 else { throw TapperError("run requires a sequence name or UUID") }
        name = args[1]; index = 2
    }
    if action == "key" {
        guard args.count > 1 else { throw TapperError("key requires a key name or shortcut") }
        _ = try KeyStroke(args[1])
        key = args[1]; index = 2
    }
    while index < args.count {
        if args[index] == "--window", action == "key" {
            guard index + 1 < args.count, !args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  windowTitle == nil else { throw TapperError("--window requires one exact Simulator title") }
            windowTitle = args[index + 1]; index += 2; continue
        }
        if args[index] == "--strict-elements", action == "run" { strictElements = true; index += 1; continue }
        guard index + 1 < args.count, let value = Double(args[index + 1]), value.isFinite,
              value >= 0, value <= 86400 else { throw TapperError("Invalid option value") }
        switch args[index] {
        case "--delay" where action == "run" && value <= 3600: delay = value
        case "--timeout" where value > 0: timeout = value
        default: throw TapperError("Unknown option or delay exceeds 3600 seconds")
        }
        index += 2
    }
    let store = try Store()
    let command = Command(action: action, recording: name, delay: delay, strictElements: strictElements, key: key, windowTitle: windowTitle)
    let request = store.inbox.appendingPathComponent("\(command.id).json")
    let response = store.outbox.appendingPathComponent("\(command.id).json")
    try store.write(command, at: request)
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while ProcessInfo.processInfo.systemUptime < deadline {
        if FileManager.default.fileExists(atPath: response.path) {
            let reply = try store.read(Reply.self, at: response)
            try? FileManager.default.removeItem(at: response)
            output(reply); exit(reply.ok ? 0 : 1)
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    try? FileManager.default.removeItem(at: request)
    output(Reply(ok: false, message: "Timed out. Open SimChoreographer and enable agent control. Playback may still be running; use simchoreographerctl stop."))
    exit(2)
} catch {
    output(Reply(ok: false, message: error.localizedDescription)); exit(1)
}
