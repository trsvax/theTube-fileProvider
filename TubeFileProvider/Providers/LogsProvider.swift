import FileProvider

actor LogsProvider {
    static let shared = LogsProvider()

    func list(path: String) async throws -> [NSFileProviderItem] {
        let parentId = NSFileProviderItemIdentifier(path)

        if path == "logs" {
            // List dates
            let dates = try await TubeRequest.shared.request("aws/list-log-dates") as? [String] ?? []
            return dates.map { date in
                TubeItem(
                    identifier: NSFileProviderItemIdentifier("logs/\(date)"),
                    parentIdentifier: parentId,
                    filename: date,
                    isFolder: true
                )
            }
        }

        // logs/{date} → list hours as .tsv files
        let components = path.split(separator: "/")
        if components.count == 2 {
            let date = String(components[1])
            let params: [String: Any] = ["date": date]
            let hours = try await TubeRequest.shared.request("aws/list-log-hours", params: params) as? [String] ?? []
            return hours.map { hour in
                TubeItem(
                    identifier: NSFileProviderItemIdentifier("logs/\(date)/\(hour).tsv"),
                    parentIdentifier: parentId,
                    filename: "\(hour).tsv",
                    isFolder: false,
                    size: 4096  // Estimated — log files vary
                )
            }
        }

        return []
    }

    func fetch(path: String) async throws -> Data {
        // path = logs/{date}/{hour}.tsv
        let components = path.split(separator: "/")
        guard components.count == 3 else {
            return Data()
        }
        let date = String(components[1])
        let hour = String(components[2]).replacingOccurrences(of: ".tsv", with: "")
        let params: [String: Any] = ["date": date, "hour": hour]
        let result = try await TubeRequest.shared.requestString("aws/get-log-content", params: params)
        return Data(result.utf8)
    }
}
