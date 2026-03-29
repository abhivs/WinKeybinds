import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventTapManager: EventTapManager?
    private let prefs = PreferencesManager.shared

    // Cached icons for dialogs
    private lazy var appIcon: NSImage? = NSApp.applicationIconImage
    private lazy var confusedIcon: NSImage? = NSImage(named: "ConfusedIcon")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for legacy PresButan prefs to import
        if prefs.hasLegacyPrefs {
            NSApp.activate(ignoringOtherApps: true)
            let migrate = NSAlert()
            migrate.icon = appIcon
            migrate.messageText = "Import settings from PresButan?"
            migrate.informativeText = "WinKeybinds found existing PresButan preferences on this system. Would you like to import them?"
            migrate.addButton(withTitle: "Import Settings")
            migrate.addButton(withTitle: "Start Fresh")
            if migrate.runModal() == .alertFirstButtonReturn {
                prefs.importLegacyPrefs()

                let summary = NSAlert()
                summary.icon = appIcon
                summary.messageText = "Settings imported!"
                summary.informativeText = """
                    Imported from PresButan:

                    Return key opens items: \(prefs.returnKeyEnabled ? "Yes" : "No")
                    Enter key opens items: \(prefs.enterKeyEnabled ? "Yes" : "No")
                    Delete key trashes items: \(prefs.deleteKeyEnabled ? "Yes" : "No")
                    Forward Delete key trashes items: \(prefs.forwardDeleteKeyEnabled ? "Yes" : "No")

                    To change these later, hold Command while launching WinKeybinds.
                    """
                summary.addButton(withTitle: "OK")
                summary.runModal()

                askLaunchAtLogin()
            } else {
                prefs.declineLegacyImport()
            }
        }

        // Check if Command key is held or first launch → show config
        let commandHeld = NSEvent.modifierFlags.contains(.command)
        if prefs.isFirstLaunch || commandHeld {
            NSApp.activate(ignoringOtherApps: true)
            showConfigurationDialogs()
            prefs.markAsLaunched()
        }

        // Check accessibility permissions (without triggering system prompt)
        if !AXIsProcessTrusted() {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.icon = confusedIcon
            alert.messageText = "Accessibility Access Required"
            alert.informativeText = "WinKeybinds needs accessibility access to intercept keyboard events in Finder.\n\nPlease grant access in System Settings → Privacy & Security → Accessibility, then relaunch WinKeybinds."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            NSApp.terminate(nil)
            return
        }

        // Start the event tap
        eventTapManager = EventTapManager()
        if !eventTapManager!.start() {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.icon = confusedIcon
            alert.messageText = "Critical Error"
            alert.informativeText = "WinKeybinds failed to install the keyboard event tap. Please ensure accessibility access is granted and try again."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTapManager?.stop()
    }

    private func showConfigurationDialogs() {
        // Welcome
        let welcome = NSAlert()
        welcome.icon = appIcon
        welcome.messageText = "Welcome to WinKeybinds!"
        welcome.informativeText = "You'll be asked which keyboard shortcuts to enable.\n\nTo change these later, hold the Command key while launching WinKeybinds."
        welcome.addButton(withTitle: "Continue")
        welcome.runModal()

        // Return key
        let returnAlert = NSAlert()
        returnAlert.icon = appIcon
        returnAlert.messageText = "Use the Return key to open items in Finder?"
        returnAlert.addButton(withTitle: "Enable")
        returnAlert.addButton(withTitle: "Skip")
        prefs.returnKeyEnabled = (returnAlert.runModal() == .alertFirstButtonReturn)

        // Enter key
        let enterAlert = NSAlert()
        enterAlert.icon = appIcon
        enterAlert.messageText = "Use the Enter key to open items in Finder?"
        enterAlert.addButton(withTitle: "Enable")
        enterAlert.addButton(withTitle: "Skip")
        prefs.enterKeyEnabled = (enterAlert.runModal() == .alertFirstButtonReturn)

        // Delete key
        let deleteAlert = NSAlert()
        deleteAlert.icon = appIcon
        deleteAlert.messageText = "Use the Delete key to move items to the Trash?"
        deleteAlert.informativeText = "This will intercept the Delete key in Finder. Use with care."
        deleteAlert.addButton(withTitle: "Enable")
        deleteAlert.addButton(withTitle: "Skip")
        prefs.deleteKeyEnabled = (deleteAlert.runModal() == .alertFirstButtonReturn)

        // Forward Delete key
        let fwdDeleteAlert = NSAlert()
        fwdDeleteAlert.icon = appIcon
        fwdDeleteAlert.messageText = "Use the Forward Delete key to move items to the Trash?"
        fwdDeleteAlert.informativeText = "This is the \"del\" key found on extended keyboards."
        fwdDeleteAlert.addButton(withTitle: "Enable")
        fwdDeleteAlert.addButton(withTitle: "Skip")
        prefs.forwardDeleteKeyEnabled = (fwdDeleteAlert.runModal() == .alertFirstButtonReturn)

        askLaunchAtLogin()
    }

    private func askLaunchAtLogin() {
        let loginAlert = NSAlert()
        loginAlert.icon = appIcon
        loginAlert.messageText = "Start WinKeybinds automatically when you log in?"
        loginAlert.informativeText = "Since WinKeybinds runs invisibly in the background, this is recommended so you don't have to remember to launch it."
        loginAlert.addButton(withTitle: "Yes, start at login")
        loginAlert.addButton(withTitle: "No thanks")
        if loginAlert.runModal() == .alertFirstButtonReturn {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
