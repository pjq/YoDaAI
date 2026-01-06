import Foundation
import SwiftData

@Model
final class LLMProvider: Identifiable {
    var id: UUID

    /// Display name shown in UI.
    var name: String

    /// OpenAI-compatible base URL, e.g. http://localhost:11434/v1
    var baseURL: String

    /// Optional bearer token.
    var apiKey: String

    /// Last selected model for this provider.
    var selectedModel: String

    /// Whether this provider is the default for new requests.
    var isDefault: Bool

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Local (Ollama)",
        baseURL: String = "http://localhost:11434/v1",
        apiKey: String = "",
        selectedModel: String = "llama3.1",
        isDefault: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.selectedModel = selectedModel
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
