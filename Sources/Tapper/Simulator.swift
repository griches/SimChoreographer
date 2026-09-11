import AppKit
import ApplicationServices
import TapperCore

struct SimulatorWindow: Identifiable {
    let id: Int
    let title: String
    let frame: CGRect
    let element: AXUIElement
    let app: NSRunningApplication
}
enum Simulator {
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func windows() -> [SimulatorWindow] {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iphonesimulator").flatMap { app in
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] else { return [SimulatorWindow]() }
            return windows.enumerated().compactMap { index, window in
                guard let rect = frame(window), rect.width > 100, rect.height > 100,
                      attribute(window, kAXMinimizedAttribute) as? Bool != true else { return nil }
                let title = attribute(window, kAXTitleAttribute) as? String ?? "Simulator"
                return SimulatorWindow(id: Int(app.processIdentifier) * 1000 + index, title: title, frame: rect, element: window, app: app)
            }
        }
    }
    static func hasKeyboardFocus(_ window: SimulatorWindow) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.processIdentifier,
              let focused = attribute(AXUIElementCreateApplication(window.app.processIdentifier), kAXFocusedWindowAttribute),
              CFEqual(focused, window.element) else { return false }
        // A modal sheet redirects typing away from the recorded device window.
        let children = attribute(window.element, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return !children.contains { attribute($0, kAXRoleAttribute) as? String == kAXSheetRole }
    }
    static func hitElement(_ window: SimulatorWindow, at point: CGPoint) -> AXUIElement? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.processIdentifier else { return nil }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        if CFEqual(hit, window.element) { return hit }
        guard let owner = attribute(hit, kAXWindowAttribute), CFEqual(owner, window.element) else { return nil }
        return hit
    }
    static func isTarget(_ window: SimulatorWindow, at point: CGPoint) -> Bool {
        hitElement(window, at: point) != nil
    }

    /// Search only the selected window. Yield between nodes so Stop remains responsive.
    @MainActor static func locate(_ recorded: ElementSnapshot?, in window: SimulatorWindow) async throws -> CGPoint {
        guard let recorded, recorded.ancestorDepth == 0, recorded.hasName else {
            throw TapperError("No direct accessibility target was recorded")
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 1.0
        var pending = [window.element]
        var visited: [AXUIElement] = []
        var elements: [AXUIElement] = []
        var snapshots: [ElementSnapshot] = []
        var complete = true
        while let element = pending.popLast() {
            try Task.checkCancellation()
            if visited.contains(where: { CFEqual($0, element) }) { continue }
            guard visited.count < 600, ProcessInfo.processInfo.systemUptime < deadline else { complete = false; break }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, 0.01)
            func read(_ key: String) -> CFTypeRef? {
                guard ProcessInfo.processInfo.systemUptime < deadline else { complete = false; return nil }
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
                if error != .success && error != .noValue && error != .attributeUnsupported { complete = false }
                return value
            }
            if !CFEqual(element, window.element) {
                let description = read(kAXDescriptionAttribute) as? String
                let title = read(kAXTitleAttribute) as? String
                let identifier = read(kAXIdentifierAttribute) as? String
                let role = read(kAXRoleAttribute) as? String
                snapshots.append(ElementSnapshot(label: ElementSnapshot(label: description).label ?? title,
                                                 identifier: identifier, role: role))
                elements.append(element)
            }
            let children = read(kAXChildrenAttribute) as? [AXUIElement] ?? []
            guard children.count + pending.count <= 1200 else { complete = false; break }
            pending.append(contentsOf: children)
            await Task.yield()
        }
        let index = try ElementTargeting.match(recorded, candidates: snapshots, complete: complete)
        let element = elements[index]
        guard let rect = frame(element), let windowRect = frame(window.element),
              !rect.isEmpty, !rect.isInfinite, !rect.isNull,
              windowRect.contains(rect), attribute(element, kAXEnabledAttribute) as? Bool != false else {
            throw TapperError("Accessibility target is off screen or unavailable")
        }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        guard var hit = hitElement(window, at: point) else { throw TapperError("Accessibility target is covered or Simulator lost focus") }
        // A label child may receive the hit for its containing button. An unrelated
        // overlay or sibling must never be accepted as the matched target.
        for _ in 0..<12 {
            if CFEqual(hit, element) { return point }
            if CFEqual(hit, window.element) { break }
            AXUIElementSetMessagingTimeout(hit, 0.01)
            guard let parent = attribute(hit, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            hit = parent as! AXUIElement
        }
        throw TapperError("Accessibility target is covered by another element")
    }

    /// Read immediately on mouse-down, before navigation can replace the target.
    /// Keep inspection bounded: a slow or incomplete AX provider must not prevent recording.
    static func snapshot(_ hit: AXUIElement, in window: SimulatorWindow) -> ElementSnapshot? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.08
        var current = hit
        var fallback: ElementSnapshot?
        for depth in 0..<5 {
            guard !CFEqual(current, window.element), ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(current, 0.015)
            func string(_ key: String) -> String? {
                guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
                return attribute(current, key) as? String
            }
            // Simulator commonly exposes iOS labels through AXDescription or AXTitle.
            // Do not read AXValue: it may contain text entered into a secure field.
            let description = string(kAXDescriptionAttribute)
            let title = string(kAXTitleAttribute)
            let identifier = string(kAXIdentifierAttribute)
            let role = string(kAXRoleAttribute)
            let descriptionLabel = ElementSnapshot(label: description).label
            let result = ElementSnapshot(label: descriptionLabel ?? title, identifier: identifier,
                                         role: role, ancestorDepth: depth)
            if result.hasName { return result }
            if depth == 0 { fallback = result }
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let parent = attribute(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID(),
                  !CFEqual(parent, current) else { break }
            let next = parent as! AXUIElement
            // Never borrow a label from another window or from Simulator's app node.
            if CFEqual(next, window.element) { break }
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            AXUIElementSetMessagingTimeout(next, 0.015)
            guard let owner = attribute(next, kAXWindowAttribute), CFEqual(owner, window.element) else { break }
            current = next
        }
        return fallback
    }
}
