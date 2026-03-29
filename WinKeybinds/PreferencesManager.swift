import Foundation

class PreferencesManager {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard
    private let keysKey = "keys"

    // Legacy PresButan domain for migration
    private static let legacyDomain = "com.what.huh.PresButan"
    private let migratedKey = "migratedFromPresButan"

    // Bitmask layout
    // Bit 0 (1):  Return key
    // Bit 1 (2):  Enter key
    // Bit 2 (4):  Delete key
    // Bit 3 (8):  Forward Delete key
    // Bit 4 (16): Has been configured

    private var bitmask: Int {
        get { defaults.integer(forKey: keysKey) }
        set { defaults.set(newValue, forKey: keysKey) }
    }

    var returnKeyEnabled: Bool {
        get { bitmask & 1 != 0 }
        set { setBit(0, enabled: newValue) }
    }

    var enterKeyEnabled: Bool {
        get { bitmask & 2 != 0 }
        set { setBit(1, enabled: newValue) }
    }

    var deleteKeyEnabled: Bool {
        get { bitmask & 4 != 0 }
        set { setBit(2, enabled: newValue) }
    }

    var forwardDeleteKeyEnabled: Bool {
        get { bitmask & 8 != 0 }
        set { setBit(3, enabled: newValue) }
    }

    var isFirstLaunch: Bool {
        return bitmask & 16 == 0
    }

    func markAsLaunched() {
        bitmask |= 16
    }

    /// Returns true if legacy PresButan prefs exist and haven't been migrated yet
    var hasLegacyPrefs: Bool {
        guard !defaults.bool(forKey: migratedKey) else { return false }
        guard let legacyDefaults = UserDefaults(suiteName: PreferencesManager.legacyDomain) else { return false }
        let legacyKeys = legacyDefaults.integer(forKey: keysKey)
        // Bit 4 (configured flag) must be set for these to be real prefs
        return legacyKeys & 16 != 0
    }

    /// Import bitmask from legacy PresButan prefs
    func importLegacyPrefs() {
        guard let legacyDefaults = UserDefaults(suiteName: PreferencesManager.legacyDomain) else { return }
        let legacyKeys = legacyDefaults.integer(forKey: keysKey)
        bitmask = legacyKeys
        defaults.set(true, forKey: migratedKey)
    }

    /// Mark migration as declined so we don't ask again
    func declineLegacyImport() {
        defaults.set(true, forKey: migratedKey)
    }

    private func setBit(_ bit: Int, enabled: Bool) {
        if enabled {
            bitmask |= (1 << bit)
        } else {
            bitmask &= ~(1 << bit)
        }
    }

    private init() {}
}
