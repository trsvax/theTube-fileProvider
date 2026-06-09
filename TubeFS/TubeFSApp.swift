import SwiftUI
import FileProvider

@main
struct TubeFSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var status: String = "Checking..."
    @State private var hasToken = false
    @State private var hasSecret = false
    @State private var domainStatus: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("TubeFS")
                .font(.title)

            if hasToken && hasSecret {
                Label("Credentials ready", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Label(status, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Button("Import from Keychain") {
                    importCredentials()
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            Text(domainStatus)
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding(40)
        .frame(minWidth: 360, minHeight: 240)
        .task {
            checkCredentials()
            await registerDomain()
        }
    }

    private func registerDomain() async {
        // Ensure shared container exists
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.thetube.fs") {
            try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            domainStatus = "Container: \(container.lastPathComponent)"
        }

        let domainId = NSFileProviderDomainIdentifier("com.thetube.fs.file-provider")

        let domain = NSFileProviderDomain(
            identifier: domainId,
            displayName: "TubeFS"
        )

        do {
            // Remove ALL existing domains for our provider (clears stale state)
            let existing = try await NSFileProviderManager.domains()
            for d in existing {
                let id = d.identifier.rawValue
                if id.contains("thetube") || id.contains("file-provider") {
                    try? await NSFileProviderManager.remove(d)
                    domainStatus += "\nRemoved stale: \(id.prefix(20))"
                }
            }

            // Add fresh with the replicated extension initializer
            try await NSFileProviderManager.add(domain)

            // Force mount by requesting the visible URL
            if let manager = NSFileProviderManager(for: domain) {
                let url = try await manager.getUserVisibleURL(for: .rootContainer)
                domainStatus += "\nMounted at: \(url.lastPathComponent) ✓"
            } else {
                domainStatus += "\nNo manager for domain"
            }
        } catch {
            domainStatus += "\nFailed: \(error.localizedDescription)"
        }
    }

    private func checkCredentials() {
        hasToken = readSharedKeychain(service: "share-token-mac") != nil
        hasSecret = readSharedKeychain(service: "share-secret-mac") != nil

        if hasToken && hasSecret {
            status = "Ready"
        } else {
            status = "Credentials not in app group"
        }
    }

    private func importCredentials() {
        guard let token = readLoginKeychain(service: "share-token-mac", account: "thetube"),
              let secret = readLoginKeychain(service: "share-secret-mac", account: "thetube") else {
            status = "Not found in login keychain"
            return
        }

        let tokenOk = writeSharedKeychain(service: "share-token-mac", account: "thetube", value: token)
        let secretOk = writeSharedKeychain(service: "share-secret-mac", account: "thetube", value: secret)

        if tokenOk && secretOk {
            hasToken = true
            hasSecret = true
            status = "Ready"
        } else {
            status = "Failed to write to shared keychain"
        }
    }

    // MARK: - Login Keychain (default, no access group)

    private func readLoginKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Shared Keychain (app group)

    private func readSharedKeychain(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "thetube",
            kSecAttrAccessGroup as String: "group.com.thetube.fs",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeSharedKeychain(service: String, account: String, value: String) -> Bool {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: "group.com.thetube.fs",
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: "group.com.thetube.fs",
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
}
