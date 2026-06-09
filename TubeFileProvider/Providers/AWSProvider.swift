import FileProvider

actor AWSProvider {
    static let shared = AWSProvider()

    func list(path: String) async throws -> [NSFileProviderItem] {
        let parentId = NSFileProviderItemIdentifier(path)

        if path == "aws" {
            return [
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/cloudfront"),
                         parentIdentifier: parentId, filename: "cloudfront", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/lambda"),
                         parentIdentifier: parentId, filename: "lambda", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/s3"),
                         parentIdentifier: parentId, filename: "s3", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/cognito"),
                         parentIdentifier: parentId, filename: "cognito", isFolder: true),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/iam"),
                         parentIdentifier: parentId, filename: "iam", isFolder: true),
            ]
        }

        if path == "aws/cloudfront" {
            return [
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/cloudfront/distribution.json"),
                         parentIdentifier: parentId, filename: "distribution.json", isFolder: false),
            ]
        }

        if path == "aws/lambda" {
            let lambdas = try await TubeRequest.shared.request("aws/list-lambdas") as? [[String: Any]] ?? []
            return lambdas.compactMap { fn in
                guard let name = fn["name"] as? String else { return nil }
                return TubeItem(
                    identifier: NSFileProviderItemIdentifier("aws/lambda/\(name).json"),
                    parentIdentifier: parentId,
                    filename: "\(name).json",
                    isFolder: false
                )
            }
        }

        if path == "aws/s3" {
            let prefixes = try await TubeRequest.shared.request("aws/list-s3-prefixes") as? [String] ?? []
            return prefixes.map { prefix in
                TubeItem(
                    identifier: NSFileProviderItemIdentifier("aws/s3/\(prefix)"),
                    parentIdentifier: parentId,
                    filename: prefix,
                    isFolder: true
                )
            }
        }

        if path == "aws/cognito" {
            return [
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/cognito/pool.json"),
                         parentIdentifier: parentId, filename: "pool.json", isFolder: false),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/cognito/clients.json"),
                         parentIdentifier: parentId, filename: "clients.json", isFolder: false),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/cognito/groups.json"),
                         parentIdentifier: parentId, filename: "groups.json", isFolder: false),
            ]
        }

        if path == "aws/iam" {
            return [
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/iam/roles.json"),
                         parentIdentifier: parentId, filename: "roles.json", isFolder: false),
                TubeItem(identifier: NSFileProviderItemIdentifier("aws/iam/users.json"),
                         parentIdentifier: parentId, filename: "users.json", isFolder: false),
            ]
        }

        return []
    }

    func fetch(path: String) async throws -> Data {
        let result: Any

        switch path {
        case "aws/cloudfront/distribution.json":
            result = try await TubeRequest.shared.request("aws/describe-cloudfront")

        case "aws/cognito/pool.json":
            result = try await TubeRequest.shared.request("aws/describe-cognito-pool")

        case "aws/cognito/clients.json":
            result = try await TubeRequest.shared.request("aws/list-cognito-clients")

        case "aws/cognito/groups.json":
            result = try await TubeRequest.shared.request("aws/list-cognito-groups")

        case "aws/iam/roles.json":
            result = try await TubeRequest.shared.request("aws/list-iam-roles")

        case "aws/iam/users.json":
            result = try await TubeRequest.shared.request("aws/list-iam-users")

        default:
            // aws/lambda/{name}.json
            if path.hasPrefix("aws/lambda/") && path.hasSuffix(".json") {
                let name = String(path.dropFirst("aws/lambda/".count).dropLast(".json".count))
                let params: [String: Any] = ["functionName": name]
                result = try await TubeRequest.shared.request("aws/get-lambda-config", params: params)
            } else {
                result = ["error": "unknown path: \(path)"]
            }
        }

        let data: Data
        if let dict = result as? [String: Any] {
            data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        } else if let arr = result as? [Any] {
            data = try JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys])
        } else if let str = result as? String {
            data = Data(str.utf8)
        } else {
            data = Data("null".utf8)
        }
        return data
    }
}
