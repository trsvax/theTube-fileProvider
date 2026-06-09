import FileProvider

actor LogsProvider {
    static let shared = LogsProvider()

    func list(path: String) async throws -> [NSFileProviderItem] {
        let result = try await TubeRequest.shared.requestArray("list/\(path)")
        let parentId = NSFileProviderItemIdentifier(path)

        return result.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let childPath = path.isEmpty ? name : "\(path)/\(name)"
            let isFolder = (item["type"] as? String) == "folder"
            return TubeItem(
                identifier: NSFileProviderItemIdentifier(childPath),
                parentIdentifier: parentId,
                filename: name,
                isFolder: isFolder,
                size: item["size"] as? Int
            )
        }
    }

    func fetch(path: String) async throws -> Data {
        let result = try await TubeRequest.shared.requestString(path)
        return Data(result.utf8)
    }
}
