import SwiftUI
import TapperCore

@main
struct TapperApp: App {
    @StateObject private var model = Controller()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 780, minHeight: 560)
        }
        .commands {
            CommandMenu("Automation") {
                Button("Stop recording or playback") { model.stop() }
                    .keyboardShortcut(.escape, modifiers: [.command, .shift])
            }
        }
    }
}
struct ContentView: View {
    @ObservedObject var model: Controller
    @State private var selected: UUID?
    @State private var delay = 0.0
    private func delete(_ id: UUID) {
        model.delete(id)
        if !model.recordings.contains(where: { $0.id == id }), selected == id { selected = nil }
    }
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                Section("SAVED SEQUENCES") {
                    ForEach(model.recordings) { sequence in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(sequence.name, systemImage: "hand.tap")
                            Text("\(sequence.summary) · \(sequence.windowTitle)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(.vertical, 5).tag(sequence.id)
                        .contextMenu {
                            Button("Delete recording", role: .destructive) { delete(sequence.id) }
                                .disabled(model.recording || model.playing)
                        }
                    }
                }
            }
            .onDeleteCommand {
                if let selected { delete(selected) }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 250)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(role: .destructive) {
                        if let selected { delete(selected) }
                    } label: { Label("Delete recording", systemImage: "trash") }
                        .disabled(selected == nil || model.recording || model.playing)
                    Button("Undo Delete") { model.undoDelete() }
                        .disabled(model.deletedRecording == nil || model.recording || model.playing)
                    Label("Stored on this Mac", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("SimChoreographer").font(.largeTitle.bold())
                            Text("Record once. Replay in Simulator.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.recording || model.playing {
                            Button("Stop  ⌘⇧Esc", role: .destructive) { model.stop() }.buttonStyle(.borderedProminent).tint(.red)
                        }
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Permissions", systemImage: "lock.shield").font(.headline)
                            Text("Accessibility lets SimChoreographer locate Simulator and replay input. Input Monitoring records clicks, holds, drags, and key presses only in the selected Simulator window. ⌘⇧Escape stops recording or playback.")
                                .font(.callout).foregroundStyle(.secondary)
                            HStack {
                                Button(model.accessibility ? "✓ Accessibility" : "Enable Accessibility") { model.requestAccessibility() }
                                Button(model.monitoring ? "✓ Input Monitoring" : "Enable Input Monitoring") { model.requestMonitoring() }
                                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Refresh permissions and Simulator windows")
                            }
                            if !model.accessibility || !model.monitoring {
                                Text("Already enabled in System Settings? Quit SimChoreographer, remove its old entry with −, then add this copy with + and reopen it. Refresh cannot repair an entry for an older build.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Show this copy in Finder") { model.revealApp() }
                            }
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Record a sequence").font(.title2.bold())
                        TextField("Sequence name", text: $model.name).textFieldStyle(.roundedBorder)
                        Picker("Simulator window", selection: $model.selectedWindow) {
                            Text("Select a window").tag(nil as Int?)
                            ForEach(model.windows) { window in Text(window.title).tag(Optional(window.id)) }
                        }
                        HStack {
                            Button { model.startRecording() } label: { Label("Record input", systemImage: "record.circle") }
                                .buttonStyle(.borderedProminent).disabled(model.recording || model.playing)
                            Text("⌘⇧Escape stops and saves").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let sequence = model.recordings.first(where: { $0.id == selected }) {
                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text(sequence.name).font(.title2.bold())
                            Text("\(sequence.summary) · window size \(Int(sequence.width)) × \(Int(sequence.height)) pt")
                                .foregroundStyle(.secondary)
                            HStack {
                                Text("Start after")
                                TextField("Seconds", value: $delay, format: .number).frame(width: 60).textFieldStyle(.roundedBorder)
                                Text("seconds")
                                Spacer()
                                Button("Delete", role: .destructive) { delete(sequence.id) }
                                Button("Replay") {
                                    do { try model.run(sequence, delay: delay) } catch { model.status = error.localizedDescription }
                                }.buttonStyle(.borderedProminent)
                            }.disabled(model.recording || model.playing)
                            Text("simchoreographerctl run \(sequence.id.uuidString)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                    Divider()
                    Toggle("Allow local AI agents to run sequences", isOn: $model.agentEnabled)
                    Text("Agent control is on by default each launch. Turn it off here to disable access for this session. When enabled, programs running as your Mac user can list and replay sequences or stop playback. Recorded keys and modifiers are stored locally and can reveal what you type. Avoid entering secrets while recording. No network server or screenshots.")
                        .font(.caption).foregroundStyle(.secondary)
                    Label(model.status, systemImage: model.recording ? "record.circle.fill" : model.playing ? "play.circle.fill" : "info.circle")
                        .foregroundStyle(model.recording ? .red : .primary).textSelection(.enabled)
                }.padding(28)
            }
        }
    }
}
