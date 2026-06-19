import Foundation

/// Stable device identifier for the X-Device-Id header.
/// Uses the hardware model + a user-friendly name stored in UserDefaults.
enum DeviceIdentifier {
    private static let key = "tube-device-id"
    private static let defaults = UserDefaults(suiteName: "group.com.thetube.fs")

    static var current: String {
        if let stored = defaults?.string(forKey: key) {
            return stored
        }
        let id = generateId()
        defaults?.set(id, forKey: key)
        return id
    }

    /// Set a custom device name (e.g. during setup).
    static func set(_ name: String) {
        defaults?.set(name, forKey: key)
    }

    private static func generateId() -> String {
        #if os(iOS)
        return "iphone"
        #elseif os(macOS)
        return "mac"
        #else
        return "device"
        #endif
    }
}
