---
title: TubeRequest.swift
date: 2026-06-05
tags: [tech, src]
type: journal
audience: owner
status: journaling
coffee: 1
summary: The Swift client. Same protocol as the Node one — POST, auth, poll. But native Keychain and CryptoKit. No shell commands. Touch ID to send.
workflow: draft
deploy:
  type: module
  name: TubeRequest.swift
  target: TubeFS/TubeFileProvider/TubeRequest.swift
  code: swift
---

## Same protocol, native auth

The Node `tubeRequest.js` shells out to `security find-generic-password` and spawns Python for URL encoding. It works, but it's a hack — child processes for auth, string parsing for crypto.

The Swift version uses what the platform gives you: P-256 key pair in Keychain (protected by access control / Touch ID), `CryptoKit` for signing, `URLSession` for HTTP. One process, no subshells, no shared secrets.

The protocol:

```
POST https://thetube.today/tube/{path}
X-Device-Id: {device-id}
X-Timestamp: {unix seconds}
X-Signature: base64(sign(private_key, "POST\n/tube/{path}\n{timestamp}\n{body_sha256}"))
Content-Type: application/json
```

200 = sync result (JSON). 202 = async (poll the result URL). 403 = auth failed.

```swift # src Shared/TubeRequest.swift
import Foundation
import CryptoKit

actor TubeRequest {
    static let shared = TubeRequest()

    private let baseURL: URL
    private let deviceId: String
    private var privateKey: P256.Signing.PrivateKey?

    private let pollInterval: TimeInterval = 0.2
    private let pollTimeout: TimeInterval = 10.0

    init(baseURL: URL = URL(string: "https://thetube.today/tube")!,
         deviceId: String = "mac") {
        self.baseURL = baseURL
        self.deviceId = deviceId
    }
```

## Keychain

Read the P-256 private key from Keychain. The key is stored with access control requiring biometric authentication — Touch ID / Face ID is triggered automatically by the OS when the key is accessed.

```swift # src Shared/TubeRequest.swift
    private func loadKey() throws {
        if privateKey != nil { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: "today.thetube.signing-key".data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let secKey = result else {
            throw TubeError.noAuth("Signing key not found in Keychain")
        }

        // Convert SecKey to CryptoKit P256 key
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(secKey as! SecKey, &error) as Data? else {
            throw TubeError.noAuth("Failed to export key: \(error.debugDescription)")
        }

        privateKey = try P256.Signing.PrivateKey(x963Representation: keyData)
    }
```

## Signing

Sign the canonical request string: `method\npath\ntimestamp\nbody_sha256`. Returns the signature as base64 and the timestamp used.

```swift # src Shared/TubeRequest.swift
    private func sign(method: String, path: String, body: Data) throws -> (timestamp: String, signature: String) {
        guard let key = privateKey else {
            throw TubeError.noAuth("No signing key loaded")
        }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let canonical = "\(method)\n\(path)\n\(timestamp)\n\(bodyHash)"
        let canonicalData = Data(canonical.utf8)

        let signature = try key.signature(for: canonicalData)
        let signatureBase64 = signature.derRepresentation.base64EncodedString()

        return (timestamp, signatureBase64)
    }
```

## The request

POST to `/tube/{path}` with signature headers and JSON body. Check status code: 200 = done, 202 = poll, 403 = failed.

```swift # src Shared/TubeRequest.swift
    func request(_ path: String, params: [String: Any] = [:]) async throws -> Any {
        try loadKey()

        let url = baseURL.appendingPathComponent(path)
        let body: Data
        if !params.isEmpty {
            body = try JSONSerialization.data(withJSONObject: params)
        } else {
            body = Data("{}".utf8)
        }

        let (timestamp, signature) = try sign(method: "POST", path: "/tube/\(path)", body: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TubeError.unexpected("Not an HTTP response")
        }

        switch http.statusCode {
        case 200:
            return try JSONSerialization.jsonObject(with: data)

        case 202:
            let receipt = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return try await pollResult(receipt: receipt)

        case 403:
            let err = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let reason = err?["error"] as? String ?? "auth failed"
            throw TubeError.authFailed(reason)

        default:
            throw TubeError.unexpected("HTTP \(http.statusCode)")
        }
    }
```

## Polling

For async routes (202), the receipt contains a presigned result URL. Poll it until the processor writes the result. Same cadence as the Node version: 200ms interval, 10s timeout.

```swift # src Shared/TubeRequest.swift
    private func pollResult(receipt: [String: Any]) async throws -> Any {
        guard let resultURLString = receipt["result"] as? String,
              let resultURL = URL(string: resultURLString) else {
            throw TubeError.unexpected("202 but no result URL")
        }

        let deadline = Date().addingTimeInterval(pollTimeout)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))

            let (data, response) = try await URLSession.shared.data(from: resultURL)

            guard let http = response as? HTTPURLResponse else { continue }

            if http.statusCode == 200 {
                return try JSONSerialization.jsonObject(with: data)
            }

            if http.statusCode != 404 && http.statusCode != 403 {
                throw TubeError.unexpected("Polling got \(http.statusCode)")
            }
        }

        throw TubeError.timeout("Timed out waiting for result")
    }
```

## Fire-and-forget

For captures and other write-and-walk-away calls. Returns the receipt without polling.

```swift # src Shared/TubeRequest.swift
    func fire(_ path: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try loadKey()

        let url = baseURL.appendingPathComponent(path)
        let body: Data
        if !params.isEmpty {
            body = try JSONSerialization.data(withJSONObject: params)
        } else {
            body = Data("{}".utf8)
        }

        let (timestamp, signature) = try sign(method: "POST", path: "/tube/\(path)", body: body)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 202 else {
            throw TubeError.unexpected("Expected 202 for fire")
        }

        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
```

## Errors

```swift # src Shared/TubeRequest.swift
    enum TubeError: Error {
        case noAuth(String)
        case authFailed(String)
        case timeout(String)
        case unexpected(String)
    }
}
```

## Convenience

Type-safe wrappers for common patterns. The raw `request()` returns `Any` (parsed JSON). These narrow it.

```swift # src Shared/TubeRequest.swift
extension TubeRequest {
    func requestArray(_ path: String, params: [String: Any] = [:]) async throws -> [[String: Any]] {
        let result = try await request(path, params: params)
        return result as? [[String: Any]] ?? []
    }

    func requestDict(_ path: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        let result = try await request(path, params: params)
        return result as? [String: Any] ?? [:]
    }

    func requestString(_ path: String, params: [String: Any] = [:]) async throws -> String {
        let result = try await request(path, params: params)
        if let str = result as? String { return str }
        if let dict = result as? [String: Any], let content = dict["content"] as? String {
            return content
        }
        return ""
    }
}
```

[journey]:
prev: tubeRequest
next: file-provider
Port of tubeRequest.js to Swift. Same protocol, same Keychain, but P-256 signing instead of shared secrets. CryptoKit signs the canonical request string, Keychain access control triggers Touch ID. No JWT, no time-hash — just a private key that never leaves the device. The actor model gives thread safety for free — multiple FileProvider enumerators can call TubeRequest.shared concurrently without races. On iOS, the private key lives in the Secure Enclave. On Mac, it's a Keychain-protected P-256 key with biometric access control.
