import FileProvider

actor AWSProvider {
    static let shared = AWSProvider()

    func list(path: String) async throws -> [NSFileProviderItem] {
        // TODO: enumerate AWS resources via tubeRequest
        let parentId = NSFileProviderItemIdentifier(path)

        if path == "aws" {
            return [
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/cloudfront"),
                         parentIdentifier: parentId, filename: "cloudfront", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/lambda"),
                         parentIdentifier: parentId, filename: "lambda", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/s3"),
                         parentIdentifier: parentId, filename: "s3", isFolder: true),
            ]
        }

        return []
    }

    func fetch(path: String) async throws -> Data {
        let result = try await TubeRequest.shared.requestString(path)
        return Data(result.utf8)
    }
}
