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
    @State private var hasKey = false
    @State private var deviceId: String = ""
    @State private var publicKeyPEM: String = ""
    @State private var domainStatus: String = ""
    @State private var debugOutput: String = ""
    @State private var showingKey = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("TubeFS")
                .font(.title)

            if hasKey {
                Label("Signing key ready", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Device: \(deviceId)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("Show Public Key") { showingKey.toggle() }
                    Button("Regenerate Key") { generateKey() }
                        .foregroundColor(.red)
                }

                if showingKey {
                    ScrollView {
                        Text(publicKeyPEM)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 100)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)

                    Button("Copy to Clipboard") {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(publicKeyPEM, forType: .string)
                        #else
                        UIPasteboard.general.string = publicKeyPEM
                        #endif
                    }
                    .font(.caption)
                }
            } else {
                Label("No signing key", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Button("Generate Signing Key") { generateKey() }
                    .buttonStyle(.borderedProminent)
            }

            Divider()

            Text(domainStatus)
                .foregroundColor(.secondary)
                .font(.caption)

            Divider()

            HStack {
                Button("Refresh Log") { debugOutput = DebugLog.read() }
                Button("Clear Log") { DebugLog.clear(); debugOutput = "" }
            }

            ScrollView {
                Text(debugOutput)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 440)
        .task {
            checkKey()
            await registerDomain()
            debugOutput = DebugLog.read()
        }
    }

    private func checkKey() {
        hasKey = KeyManager.hasKey()
        deviceId = DeviceIdentifier.current
        if hasKey {
            publicKeyPEM = (try? KeyManager.exportPublicKey()) ?? ""
        }
    }

    private func generateKey() {
        do {
            publicKeyPEM = try KeyManager.generateKey()
            hasKey = true
            deviceId = DeviceIdentifier.current
            showingKey = true
        } catch {
            domainStatus = "Key generation failed: \(error.localizedDescription)"
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
}
