import Foundation
import CryptoKit

actor TubeRequest {
    static let shared = TubeRequest()

    private let baseURL: URL
    private let deviceId: String
    private var signingKey: P256.Signing.PrivateKey?

    private let pollInterval: TimeInterval = 0.2
    private let pollTimeout: TimeInterval = 10.0

    init(baseURL: URL = URL(string: "https://thetube.today/tube")!,
         deviceId: String = DeviceIdentifier.current) {
        self.baseURL = baseURL
        self.deviceId = deviceId
    }

    // MARK: - Key loading

    private func loadKey() throws {
        if signingKey != nil { return }
        signingKey = try KeyManager.loadPrivateKey()
    }

    // MARK: - Signing

    private func sign(method: String, path: String, body: Data) throws -> (timestamp: String, signature: String) {
        guard let key = signingKey else {
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

    // MARK: - Request

    func request(_ path: String, params: [String: Any] = [:]) async throws -> Any {
        try loadKey()

        let url = baseURL.appendingPathComponent(path)
        let body: Data
        if !params.isEmpty {
            body = try JSONSerialization.data(withJSONObject: params)
        } else {
            body = Data("{}".utf8)
        }

        let fullPath = "/tube/\(path)"
        let (timestamp, signature) = try sign(method: "POST", path: fullPath, body: body)

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

        let preview = String(data: data.prefix(200), encoding: .utf8) ?? "(binary \(data.count) bytes)"
        DebugLog.log("TubeRequest: \(path) → HTTP \(http.statusCode) (\(data.count) bytes): \(preview)")

        switch http.statusCode {
        case 200:
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        case 202:
            let receipt = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return try await pollResult(receipt: receipt)

        case 403:
            let err = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let reason = err?["error"] as? String ?? "auth failed"
            throw TubeError.authFailed(reason)

        default:
            NSLog("TubeRequest: unexpected response: %@", String(data: data.prefix(200), encoding: .utf8) ?? "binary")
            throw TubeError.unexpected("HTTP \(http.statusCode)")
        }
    }

    // MARK: - Polling

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

    // MARK: - Fire and forget

    func fire(_ path: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try loadKey()

        let url = baseURL.appendingPathComponent(path)
        let body: Data
        if !params.isEmpty {
            body = try JSONSerialization.data(withJSONObject: params)
        } else {
            body = Data("{}".utf8)
        }

        let fullPath = "/tube/\(path)"
        let (timestamp, signature) = try sign(method: "POST", path: fullPath, body: body)

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

    // MARK: - Errors

    enum TubeError: Error {
        case noAuth(String)
        case authFailed(String)
        case timeout(String)
        case unexpected(String)
    }
}

// MARK: - Convenience

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
