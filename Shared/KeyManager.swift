import Foundation
import CryptoKit

/// Manages the P-256 signing key pair in the shared Keychain.
/// The private key is stored with biometric access control (Touch ID / Face ID).
/// The public key can be exported for server registration.
enum KeyManager {

    private static let tag = "today.thetube.signing-key".data(using: .utf8)!
    private static let accessGroup = "group.com.thetube.fs"

    // MARK: - Key operations

    /// Load the private key from Keychain. Returns nil if not yet generated.
    static func loadPrivateKey() throws -> P256.Signing.PrivateKey {
        guard let keyData = readKeyFromKeychain() else {
            throw KeyError.notFound
        }
        return try P256.Signing.PrivateKey(x963Representation: keyData)
    }

    /// Check if a signing key exists in the Keychain.
    static func hasKey() -> Bool {
        readKeyFromKeychain() != nil
    }

    /// Generate a new P-256 key pair and store the private key in Keychain.
    /// Returns the public key PEM for registration with the server.
    @discardableResult
    static func generateKey() throws -> String {
        // Remove existing key if any
        deleteKey()

        let privateKey = P256.Signing.PrivateKey()
        let keyData = privateKey.x963Representation

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrApplicationTag as String: tag,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyError.keychainWrite(status)
        }

        return publicKeyPEM(from: privateKey)
    }

    /// Export the public key as a PEM string for server registration.
    static func exportPublicKey() throws -> String {
        let privateKey = try loadPrivateKey()
        return publicKeyPEM(from: privateKey)
    }

    /// Delete the signing key from Keychain.
    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Private

    private static func readKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrAccessGroup as String: accessGroup,
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
    }
}
