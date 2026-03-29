import Cocoa

class EventTapManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let finder = FinderHelper.shared
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    // Cached prefs — only change during config dialogs which require relaunch
    private var returnEnabled = false
    private var enterEnabled = false
    private var deleteEnabled = false
    private var forwardDeleteEnabled = false

    // Key codes
    private static let kReturnKey: UInt16 = 0x24
    private static let kEnterKey: UInt16 = 0x4C
    private static let kDeleteKey: UInt16 = 0x33
    private static let kForwardDeleteKey: UInt16 = 0x75

    // Tag to identify our own synthetic events and avoid re-entrance
    private static let syntheticEventTag: Int64 = 0x50_42 // "PB"

    func start() -> Bool {
        let prefs = PreferencesManager.shared
        returnEnabled = prefs.returnKeyEnabled
        enterEnabled = prefs.enterKeyEnabled
        deleteEnabled = prefs.deleteKeyEnabled
        forwardDeleteEnabled = prefs.forwardDeleteKeyEnabled

        guard installTapOnFinder() else {
            return false
        }

        // Watch for Finder relaunch so we can re-attach the tap
        let ws = NSWorkspace.shared
        ws.notificationCenter.addObserver(
            self,
            selector: #selector(appDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        ws.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        return true
    }

    func stop() {
        removeTap()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.finder" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.removeTap()
            _ = self?.installTapOnFinder()
        }
    }

    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.apple.finder" else { return }
        removeTap()
    }

    private func installTapOnFinder() -> Bool {
        guard let finderApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.finder"
        }) else {
            return false
        }

        let finderPID = finderApp.processIdentifier
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreateForPid(
            pid: finderPID,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func handleKeyEvent(_ proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if system disabled it due to timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // Ignore our own synthetic events
        if event.getIntegerValueField(.eventSourceUserData) == EventTapManager.syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Ctrl+Cmd+Delete → quit
        if keyCode == EventTapManager.kDeleteKey
            && flags.contains(.maskCommand)
            && flags.contains(.maskControl) {
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return nil
        }

        // Don't intercept if modifiers are held
        let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        if !flags.intersection(modifierMask).isEmpty {
            return Unmanaged.passUnretained(event)
        }

        // Fast path: bail out immediately for keycodes we don't handle.
        // This avoids expensive AX queries on every letter/number keypress.
        let action: Action
        switch keyCode {
        case EventTapManager.kReturnKey where returnEnabled:
            action = .open
        case EventTapManager.kEnterKey where enterEnabled:
            action = .open
        case EventTapManager.kDeleteKey where deleteEnabled:
            action = .trash
        case EventTapManager.kForwardDeleteKey where forwardDeleteEnabled:
            action = .trash
        default:
            return Unmanaged.passUnretained(event)
        }

        // Only now do the expensive AX check
        guard finder.isSafeToIntercept() else {
            return Unmanaged.passUnretained(event)
        }

        switch action {
        case .open:  postOpenCommand()
        case .trash: postTrashCommand()
        }
        return nil
    }

    private enum Action {
        case open, trash
    }

    private func postOpenCommand() {
        postKeystroke(keyCode: 0x7D, flags: .maskCommand) // Cmd+Down
    }

    private func postTrashCommand() {
        postKeystroke(keyCode: 0x33, flags: .maskCommand) // Cmd+Delete
    }

    private func postKeystroke(keyCode: UInt16, flags: CGEventFlags) {
        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.setIntegerValueField(.eventSourceUserData, value: EventTapManager.syntheticEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: EventTapManager.syntheticEventTag)

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleKeyEvent(proxy, type: type, event: event)
}
