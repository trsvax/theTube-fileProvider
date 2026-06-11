import FileProvider

actor TubeStorageProvider {
    static let shared = TubeStorageProvider()

    func list(path: String) async throws -> [NSFileProviderItem] {
        let parentId = NSFileProviderItemIdentifier(path)

        if path == "tube" {
            // List top-level tube apps (locker, routes, etc.)
            let apps = try await TubeRequest.shared.request("aws/list-tube-apps") as? [String] ?? []
            return apps.map { app in
                TubeItem(
                    identifier: NSFileProviderItemIdentifier("tube/\(app)"),
                    parentIdentifier: parentId,
                    filename: app,
                    isFolder: true
                )
            }
        }

        // tube/{app} → list actions
        let components = path.split(separator: "/")
        if components.count == 2 {
            let app = String(components[1])
            let params: [String: Any] = ["app": app]
            let actions = try await TubeRequest.shared.request("aws/list-tube-actions", params: params) as? [String] ?? []
            return actions.map { action in
                TubeItem(
                    identifier: NSFileProviderItemIdentifier("tube/\(app)/\(action)"),
                    parentIdentifier: parentId,
                    filename: action,
                    isFolder: true
                )
            }
        }

        // tube/{app}/{action} → list files
        if components.count == 3 {
            let app = String(components[1])
            let action = String(components[2])
            let params: [String: Any] = ["app": app, "action": action]
            let items = try await TubeRequest.shared.request("aws/list-tube-files", params: params) as? [[String: Any]] ?? []
            return items.compactMap { item in
                guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                let isDir = (item["type"] as? String) == "directory"
                let size = item["size"] as? Int
                return TubeItem(
                    identifier: NSFileProviderItemIdentifier("\(path)/\(name)"),
                    parentIdentifier: parentId,
                    filename: name,
                    isFolder: isDir,
                    size: size
                )
            }
        }

        return []
    }

    func fetch(path: String) async throws -> Data {
        // Convert filesystem path to S3 key
        let key = path  // tube/{app}/{action}/{file} maps directly
        let params: [String: Any] = ["key": key]
        let result = try await TubeRequest.shared.request("aws/read-tube-file", params: params)

        if let str = result as? String {
            return Data(str.utf8)
        }
        if let dict = result as? [String: Any] {
            return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        }
        if let arr = result as? [Any] {
            return try JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys])
        }

        NSLog("TubeFS read-tube-file: unexpected result type for key: %@", key)
        return Data()
    }
}
