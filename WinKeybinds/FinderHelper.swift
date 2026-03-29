import Cocoa

class FinderHelper {
    static let shared = FinderHelper()

    private let systemWide = AXUIElementCreateSystemWide()

    private init() {}

    func isSafeToIntercept() -> Bool {
        return !isFocusedElementTextField() && isFinderWindowOrDesktop()
    }

    private func isFocusedElementTextField() -> Bool {
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success,
              let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            return false
        }

        var role: AnyObject?
        let roleResult = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)

        guard roleResult == .success, let roleString = role as? String else {
            return false
        }

        return roleString == kAXTextFieldRole || roleString == kAXTextAreaRole
    }

    private func isFinderWindowOrDesktop() -> Bool {
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

        guard appResult == .success,
              let app = focusedApp,
              CFGetTypeID(app) == AXUIElementGetTypeID() else {
            return true
        }

        var focusedWindow: AnyObject?
        let winResult = AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        // No focused window likely means desktop is focused
        guard winResult == .success,
              let window = focusedWindow,
              CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return true
        }

        var roleDescription: AnyObject?
        let descResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXRoleDescriptionAttribute as CFString, &roleDescription)

        if descResult == .success, let desc = roleDescription as? String {
            if desc.lowercased() == "dialog" {
                return false
            }
        }

        var subrole: AnyObject?
        let subroleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSubroleAttribute as CFString, &subrole)

        if subroleResult == .success, let sub = subrole as? String {
            if sub == kAXDialogSubrole || sub == kAXSystemDialogSubrole {
                return false
            }
        }

        return true
    }
}
