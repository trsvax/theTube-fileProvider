import FileProvider

actor ProviderRouter {
    static let shared = ProviderRouter()

    func listItems(path: String) async throws -> [NSFileProviderItem] {
        // Root listing
        if path.isEmpty {
            return [
                TubeItem(identifier: NSFileProviderItemIdentifier("logs"),
                         parentIdentifier: .rootContainer, filename: "logs", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws"),
                         parentIdentifier: .rootContainer, filename: "aws", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("tube"),
                         parentIdentifier: .rootContainer, filename: "tube", isFolder: true),
            ]
        }

        // Route to provider
        if path == "aws" || path.hasPrefix("aws/") {
            return try await AWSProvider.shared.list(path: path)
        }
        if path == "logs" || path.hasPrefix("logs/") {
            return try await LogsProvider.shared.list(path: path)
        }
        if path == "tube" || path.hasPrefix("tube/") {
            return try await TubeStorageProvider.shared.list(path: path)
        }

        return []
    }

    func fetchContent(path: String) async throws -> Data {
        if path.hasPrefix("aws/") {
            return try await AWSProvider.shared.fetch(path: path)
        }
        if path.hasPrefix("logs/") {
            return try await LogsProvider.shared.fetch(path: path)
        }
        if path.hasPrefix("tube/") {
            return try await TubeStorageProvider.shared.fetch(path: path)
        }

        throw TubeRequest.TubeError.unexpected("No provider for path: \(path)")
    }
}
