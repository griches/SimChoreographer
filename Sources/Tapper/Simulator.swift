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
    static func isTarget(_ window: SimulatorWindow, at point: CGPoint) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == window.app.processIdentifier else { return false }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return false }
        if CFEqual(hit, window.element) { return true }
        guard let owner = attribute(hit, kAXWindowAttribute) else { return false }
        return CFEqual(owner, window.element)
    }
}
