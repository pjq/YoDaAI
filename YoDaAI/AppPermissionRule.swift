import Foundation
import SwiftData

@Model
final class AppPermissionRule {
    var id: UUID
    var bundleIdentifier: String
    var displayName: String

    /// If true, YouDaAI will attach context from this app.
    var allowContext: Bool

    /// If true, YouDaAI will insert text into this app.
    var allowInsert: Bool

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        allowContext: Bool = true,
        allowInsert: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.allowContext = allowContext
        self.allowInsert = allowInsert
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
