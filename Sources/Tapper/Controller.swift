import AppKit
import ApplicationServices
import TapperCore

final class Controller: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var windows: [SimulatorWindow] = []
    @Published var selectedWindow: Int?
    @Published var name = "New sequence"
    @Published var status = "Ready"
    @Published var recording = false
    @Published var playing = false
    @Published var count = 0
    @Published var accessibility = false
    @Published var monitoring = false
    @Published var agentEnabled = false
    @Published var deletedRecording: (recording: Recording, index: Int)?
    let store: Store?
    private var draft: Recording?
    private var target: SimulatorWindow?
    private var lastEvent = 0.0
    private var tapPort: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var timer: Timer?
    private var playback: Task<Void, Never>?
    private var runID: UUID?
    private var recordingMouseHeld = false
    private var recordingGestureFrame: CGRect?
    private var playbackMouse: MousePlayback?
    private var playbackTarget: SimulatorWindow?
    private var playbackGestureFrame: CGRect?
    private var terminationObserver: NSObjectProtocol?
    private var loadingFailed = false
    private var activationObserver: NSObjectProtocol?

    init(store suppliedStore: Store? = nil) {
        do { store = try suppliedStore ?? Store() } catch { store = nil; status = error.localizedDescription }
        if let store {
            do { recordings = try store.load() }
            catch { loadingFailed = true; status = "Cannot load recordings: \(error.localizedDescription). Existing file preserved." }
        }
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.stop(message: "App is quitting") }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }
    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        playbackMouse?.release()
        timer?.invalidate()
    }
    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    func refresh() {
        accessibility = AXIsProcessTrusted(); monitoring = CGPreflightListenEventAccess()
        windows = accessibility ? Simulator.windows() : []
        if !windows.contains(where: { $0.id == selectedWindow }) { selectedWindow = windows.first?.id }
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    func requestMonitoring() { _ = CGRequestListenEventAccess() }
    func beginCapture() throws {
        guard tapPort == nil else { return }
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, context in
            if let context { Unmanaged<Controller>.fromOpaque(context).takeUnretainedValue().event(type, event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw TapperError("Enable Input Monitoring and Accessibility for SimChoreographer, then relaunch it.")
        }
        tapPort = port
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }
    func endCapture() {
        if let tapPort { CFMachPortInvalidate(tapPort) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tapPort = nil; tapSource = nil; recordingMouseHeld = false; recordingGestureFrame = nil
    }
    func event(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop(message: "Stopped: input monitoring was interrupted")
            return
        }
        if event.getIntegerValueField(.eventSourceUserData) == Keyboard.eventMarker { return }
        if type == .keyDown, Keyboard.isStopShortcut(
            keyCode: UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode)), modifiers: event.flags.rawValue) {
            stop(); return
        }
        guard recording, let target, let draft else { return }
        guard let frame = Simulator.frame(target.element), abs(frame.width - draft.width) < 1,
              abs(frame.height - draft.height) < 1 else { stop(message: "Stopped: Simulator window size changed"); return }
        if type == .keyDown {
            guard Simulator.hasKeyboardFocus(target) else { return }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard (0...127).contains(code) else { return }
            append(Tap(keyCode: UInt16(code), modifiers: event.flags.rawValue & Keyboard.allowedModifiers, delay: 0),
                   at: ProcessInfo.processInfo.systemUptime)
            return
        }
        let point = event.location
        let time = ProcessInfo.processInfo.systemUptime
        if type == .leftMouseDown {
            guard frame.contains(point), Simulator.isTarget(target, at: point) else { return }
            guard !recordingMouseHeld else { stop(message: "Stopped: unexpected mouse press"); return }
            recordingMouseHeld = true; recordingGestureFrame = frame
            append(Tap(x: point.x - frame.minX, y: point.y - frame.minY, phase: .down, delay: 0), at: time)
        } else if type == .leftMouseDragged || type == .leftMouseUp {
            guard recordingMouseHeld else { return }
            guard frame == recordingGestureFrame, frame.contains(point), Simulator.isTarget(target, at: point) else {
                stop(message: "Stopped: gesture left the Simulator or its window moved; unfinished gesture discarded")
                return
            }
            let phase: MousePhase = type == .leftMouseUp ? .up : .drag
            append(Tap(x: point.x - frame.minX, y: point.y - frame.minY, phase: phase, delay: 0), at: time)
            if phase == .up { recordingMouseHeld = false; recordingGestureFrame = nil }
        }
    }
    private func append(_ input: Tap, at time: Double) {
        var input = input
        // Every mouse phase and key shares one chronological timeline.
        input.delay = count == 0 ? 0 : max(0, time - lastEvent)
        guard input.delay <= 3600, count < 10000 else { stop(message: "Stopped: recording limit reached"); return }
        draft?.taps.append(input)
        lastEvent = max(lastEvent, time); count += 1
        status = "Recording · \(draft?.summary ?? "") · ⌘⇧Esc to stop"
    }

    func startRecording() {
        do {
            guard !recording, !playing else { throw TapperError("SimChoreographer is busy") }
            guard !loadingFailed, store != nil else { throw TapperError("Recording storage is unavailable") }
            refresh()
            guard accessibility, monitoring else { throw TapperError("Enable both permissions, then refresh") }
            guard let window = windows.first(where: { $0.id == selectedWindow }) else { throw TapperError("Open an iOS Simulator window first") }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw TapperError("Enter a sequence name") }
            try beginCapture()
            target = window; draft = Recording(name: trimmed, windowTitle: window.title, width: window.frame.width, height: window.frame.height)
            count = 0; lastEvent = 0; recording = true; status = "Recording · click, hold, drag, or type in Simulator · ⌘⇧Esc to save"
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
            window.app.activate(options: .activateIgnoringOtherApps)
        } catch { status = error.localizedDescription }
    }
    func stop(message: String = "Stopped") {
        if recording {
            draft?.discardIncompleteGesture()
            recording = false; endCapture()
            if let draft, !draft.taps.isEmpty {
                recordings.append(draft)
                do { try store?.write(recordings, at: store!.recordingsURL); status = "Saved \(draft.summary) · \(message)" }
                catch { status = "Save failed: \(error.localizedDescription). Sequence remains in memory." }
            } else { status = "No input recorded" }
            draft = nil; target = nil
        }
        if playing { playback?.cancel(); playbackMouse?.release(); status = message }
    }
    func delete(_ id: UUID) {
        guard !recording, !playing, !loadingFailed, let store else { return }
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        var updated = recordings
        let removed = updated.remove(at: index)
        do {
            try store.write(updated, at: store.recordingsURL)
            recordings = updated; deletedRecording = (removed, index)
            status = "Deleted \(removed.name)"
        } catch { status = error.localizedDescription }
    }
    func undoDelete() {
        guard !recording, !playing, let deletedRecording, let store else { return }
        var updated = recordings
        updated.insert(deletedRecording.recording, at: min(deletedRecording.index, updated.count))
        do {
            try store.write(updated, at: store.recordingsURL)
            recordings = updated; self.deletedRecording = nil
            status = "Restored \(deletedRecording.recording.name)"
        } catch { status = error.localizedDescription }
    }
    func run(_ sequence: Recording, delay: Double = 0, completion: @escaping (Reply) -> Void = { _ in }) throws {
        guard !recording, !playing else { throw TapperError("SimChoreographer is busy") }
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess() else { throw TapperError("SimChoreographer needs Accessibility and Input Monitoring permissions") }
        try sequence.validate()
        guard delay.isFinite, delay >= 0, delay <= 3600 else { throw TapperError("Delay must be between 0 and 3600 seconds") }
        let matches = Simulator.windows().filter { $0.title == sequence.windowTitle }
        guard matches.count == 1, let window = matches.first else { throw TapperError("Open exactly one Simulator window titled '\(sequence.windowTitle)'") }
        guard abs(window.frame.width - sequence.width) < 1, abs(window.frame.height - sequence.height) < 1 else { throw TapperError("Restore the Simulator window to its recorded size") }
        try beginCapture()
        playing = true; let id = UUID(); runID = id
        let mouse = MousePlayback()
        playbackMouse = mouse; playbackTarget = window; playbackGestureFrame = nil
        status = delay > 0 ? "Scheduled in \(Int(delay)) seconds · ⌘⇧Esc to cancel" : "Starting playback"
        playback = Task { @MainActor [weak self] in
            guard let self else { return }
            var reply: Reply
            do {
                try await self.sleep(delay)
                AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
                window.app.activate(options: .activateIgnoringOtherApps)
                try await self.sleep(0.5)
                for (index, tap) in sequence.taps.enumerated() {
                    try await self.sleep(tap.delay)
                    try Task.checkCancellation()
                    guard AXIsProcessTrusted(), let rect = Simulator.frame(window.element),
                          abs(rect.width - sequence.width) < 1, abs(rect.height - sequence.height) < 1 else { throw TapperError("Simulator closed, resized, or permission revoked") }
                    if let keyCode = tap.keyCode {
                        guard Simulator.hasKeyboardFocus(window) else { throw TapperError("Simulator keyboard focus changed") }
                        // Construct the entire stroke before posting, then release all keys
                        // synchronously so cancellation cannot leave a modifier held down.
                        let events = try Keyboard.events(keyCode: keyCode, modifiers: tap.modifiers ?? 0)
                        events.forEach { $0.post(tap: .cghidEventTap) }
                    } else {
                    let point = CGPoint(x: rect.minX + tap.x, y: rect.minY + tap.y)
                    guard Simulator.isTarget(window, at: point) else { throw TapperError("Simulator lost focus or the tap is covered by another window") }
                    if mouse.isHeld, rect != self.playbackGestureFrame { throw TapperError("Simulator moved during a gesture") }
                    try mouse.send(tap.mousePhase, at: point)
                    self.playbackGestureFrame = mouse.isHeld ? rect : nil
                    }
                    self.status = "Playing \(sequence.name) · \(index + 1)/\(sequence.taps.count)"
                }
                reply = Reply(ok: true, message: "Completed \(sequence.summary)")
            } catch is CancellationError { reply = Reply(ok: false, message: "Playback cancelled") }
            catch { reply = Reply(ok: false, message: error.localizedDescription) }
            mouse.release()
            if self.runID == id {
                self.playbackMouse = nil; self.playbackTarget = nil; self.playbackGestureFrame = nil
                self.playing = false; self.playback = nil; self.runID = nil; self.endCapture(); self.status = reply.message
            }
            completion(reply)
        }
    }
    private func sleep(_ seconds: Double) async throws { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func poll() {
        // Check even while playback is waiting through a long hold.
        if playing, let mouse = playbackMouse, mouse.isHeld, let target = playbackTarget, let point = mouse.location {
            if !AXIsProcessTrusted() || Simulator.frame(target.element) != playbackGestureFrame || !Simulator.isTarget(target, at: point) {
                stop(message: "Stopped: Simulator changed during a gesture")
            }
        }
        guard let store else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: store.inbox, includingPropertiesForKeys: nil) else { return }
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let command = try store.read(Command.self, at: file)
                try FileManager.default.removeItem(at: file)
                let respond: (Reply) -> Void = { [weak self] reply in
                    do { try store.write(reply, at: store.outbox.appendingPathComponent("\(command.id).json")) }
                    catch { self?.status = "Cannot write agent reply: \(error.localizedDescription)" }
                }
                guard command.expires > Date() else { respond(Reply(ok: false, message: "Command expired")); continue }
                guard agentEnabled else { respond(Reply(ok: false, message: "Enable agent control in SimChoreographer")); continue }
                switch command.action {
                case "status": respond(Reply(ok: true, message: status))
                case "list": respond(Reply(ok: true, message: "Saved sequences", recordings: recordings))
                case "stop": stop(); respond(Reply(ok: true, message: "Stop requested"))
                case "run":
                    let matches = recordings.filter { $0.id.uuidString.lowercased() == command.recording?.lowercased() || $0.name == command.recording }
                    guard matches.count == 1, let sequence = matches.first else { respond(Reply(ok: false, message: "Sequence missing or name ambiguous; use its UUID")); continue }
                    do { try run(sequence, delay: command.delay, completion: respond) }
                    catch { respond(Reply(ok: false, message: error.localizedDescription)) }
                default: respond(Reply(ok: false, message: "Unknown command"))
                }
            } catch { try? FileManager.default.removeItem(at: file); status = "Rejected unreadable agent command" }
        }
    }
}
