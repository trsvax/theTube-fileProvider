import Foundation
import CryptoKit

/// Manages the P-256 signing key pair.
/// On iOS: Keychain with app group for cross-extension access.
/// On macOS: shared app group container file (Keychain access groups
/// don't work reliably across sandboxed app + extension without paid provisioning).
enum KeyManager {

    private static let tag = "today.thetube.signing-key".data(using: .utf8)!
    private static let sharedKeyFilename = "signing-key.dat"

    // MARK: - Key operations

    /// Load the private key. Returns nil if not yet generated.
    static func loadPrivateKey() throws -> P256.Signing.PrivateKey {
        guard let keyData = readKey() else {
            throw KeyError.notFound
        }
        return try P256.Signing.PrivateKey(x963Representation: keyData)
    }

    /// Check if a signing key exists.
    static func hasKey() -> Bool {
        readKey() != nil
    }

    /// Generate a new P-256 key pair and store the private key.
    /// Returns the public key PEM for registration with the server.
    @discardableResult
    static func generateKey() throws -> String {
        deleteKey()

        let privateKey = P256.Signing.PrivateKey()
        let keyData = privateKey.x963Representation

        #if os(iOS)
        // iOS: store in Keychain with app group for extension access
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrApplicationTag as String: tag,
            kSecAttrAccessGroup as String: "group.com.thetube.fs",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyError.keychainWrite(status)
        }
        #else
        // macOS: store in shared container file
        guard writeKeyToSharedContainer(keyData) else {
            throw KeyError.containerWrite
        }
        #endif

        return publicKeyPEM(from: privateKey)
    }

    /// Export the public key as a PEM string for server registration.
    static func exportPublicKey() throws -> String {
        let privateKey = try loadPrivateKey()
        return publicKeyPEM(from: privateKey)
    }

    /// Delete the signing key.
    static func deleteKey() {
        #if os(iOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrAccessGroup as String: "group.com.thetube.fs",
        ]
        SecItemDelete(query as CFDictionary)
        #else
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.thetube.fs"
        ) {
            let keyURL = container.appendingPathComponent(sharedKeyFilename)
            try? FileManager.default.removeItem(at: keyURL)
        }
        #endif
    }

    // MARK: - Private

    private static func readKey() -> Data? {
        #if os(iOS)
        return readKeyFromKeychain()
        #else
        return readKeyFromSharedContainer()
        #endif
    }

    #if os(iOS)
    private static func readKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrAccessGroup as String: "group.com.thetube.fs",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }
    #endif

    @discardableResult
    private static func writeKeyToSharedContainer(_ keyData: Data) -> Bool {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.thetube.fs"
        ) else { return false }
        let keyURL = container.appendingPathComponent(sharedKeyFilename)
        do {
            try keyData.write(to: keyURL, options: .completeFileProtection)
            return true
        } catch {
            return false
        }
    }

    private static func readKeyFromSharedContainer() -> Data? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.thetube.fs"
        ) else { return nil }
        let keyURL = container.appendingPathComponent(sharedKeyFilename)
        return try? Data(contentsOf: keyURL)
    }

    private static func publicKeyPEM(from privateKey: P256.Signing.PrivateKey) -> String {
        let publicKey = privateKey.publicKey
        let derData = publicKey.derRepresentation
        let base64 = derData.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PUBLIC KEY-----\n\(base64)\n-----END PUBLIC KEY-----"
    }

    // MARK: - Errors

    enum KeyError: Error {
        case notFound
        case keychainWrite(OSStatus)
        case containerWrite
    }
}
