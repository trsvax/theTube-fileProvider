import Foundation
import CryptoKit

actor TubeRequest {
    static let shared = TubeRequest()

    private let baseURL: URL
    private var token: String?
    private var secret: String?

    private let pollInterval: TimeInterval = 0.2
    private let pollTimeout: TimeInterval = 10.0

    init(baseURL: URL = URL(string: "https://thetube.today/tube")!) {
        self.baseURL = baseURL
    }
    private func loadAuth() throws {
        if token != nil && secret != nil { return }

        token = try keychainRead(service: "share-token-mac", account: "thetube")
        secret = try keychainRead(service: "share-secret-mac", account: "thetube")
    }

    private func keychainRead(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: "group.com.thetube.fs",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw TubeError.noAuth("Keychain read failed: \(service)")
        }

        return value
    }
    private func computeTimeHash(_ secret: String) -> (timestamp: String, pass: String) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let input = Data((secret + timestamp).utf8)
        let hash = SHA256.hash(data: input)
        let pass = hash.map { String(format: "%02x", $0) }.joined()
        return (timestamp, pass)
    }
    func request(_ path: String, params: [String: Any] = [:]) async throws -> Any {
        try loadAuth()

        guard let token, let secret else {
            throw TubeError.noAuth("No token or secret loaded")
        }

        let (timestamp, pass) = computeTimeHash(secret)
        let url = baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(pass, forHTTPHeaderField: "X-Pass")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !params.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } else {
            request.httpBody = Data("{}".utf8)
        }

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
    func fire(_ path: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        try loadAuth()

        guard let token, let secret else {
            throw TubeError.noAuth("No token or secret loaded")
        }

        let (timestamp, pass) = computeTimeHash(secret)
        let url = baseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(pass, forHTTPHeaderField: "X-Pass")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !params.isEmpty {
            request.httpBody = try JSONSerialization.data(withJSONObject: params)
        } else {
            request.httpBody = Data("{}".utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 202 else {
            throw TubeError.unexpected("Expected 202 for fire")
        }

        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
    enum TubeError: Error {
        case noAuth(String)
        case authFailed(String)
        case timeout(String)
        case unexpected(String)
    }
}
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
