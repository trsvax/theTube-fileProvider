import Foundation

enum DebugLog {
    private static let logURL: URL? = {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.thetube.fs")?
            .appendingPathComponent("debug.log")
    }()

    static func log(_ message: String) {
        guard let url = logURL else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func clear() {
        guard let url = logURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    static func read() -> String {
        guard let url = logURL else { return "(no container)" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "(empty)"
    }
}
