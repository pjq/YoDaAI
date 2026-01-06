import Foundation
import SwiftData

@Model
final class ProviderSettings {
    var id: UUID

    var baseURL: String
    var apiKey: String
    var model: String

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        baseURL: String = "http://localhost:11434/v1",
        apiKey: String = "",
        model: String = "llama3.1",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
