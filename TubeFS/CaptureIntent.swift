import AppIntents
import Foundation

/// "Capture to Tube" — available in Shortcuts, Siri, Spotlight, and Action Button.
/// Captures a URL or text to the tube via signed P-256 request.
struct CaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture to Tube"
    static let description: IntentDescription = "Save a link or note to the tube."

    @Parameter(title: "Content", description: "A URL or text to capture")
    var content: String

    @Parameter(title: "Type", default: .link)
    var captureType: CaptureType

    static var parameterSummary: some ParameterSummary {
        Summary("Capture \(\.$content) as \(\.$captureType)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let params: [String: Any] = [
            "type": captureType.rawValue,
            "file": content,
            "date": String(today),
        ]

        let result = try await TubeRequest.shared.fire("share/add", params: params)
        let status = result["status"] as? String ?? "sent"
        return .result(value: status)
    }
}

/// Capture type for the intent parameter.
enum CaptureType: String, AppEnum {
    case link
    case note
    case image

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Type"

    static let caseDisplayRepresentations: [CaptureType: DisplayRepresentation] = [
        .link: "Link",
        .note: "Note",
        .image: "Image",
    ]
}

/// App Shortcuts — these phrases work with Siri without any user setup.
struct TubeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Save to \(.applicationName)",
                "Send to \(.applicationName)",
            ],
            shortTitle: "Capture",
            systemImageName: "square.and.arrow.down"
        )
    }
}
