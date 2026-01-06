import Foundation
import SwiftData

final class AppPermissionsStore {
    func rule(for bundleIdentifier: String, in context: ModelContext) throws -> AppPermissionRule? {
        let descriptor = FetchDescriptor<AppPermissionRule>(
            predicate: #Predicate<AppPermissionRule> { rule in
                rule.bundleIdentifier == bundleIdentifier
            },
            sortBy: [SortDescriptor(\AppPermissionRule.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    func ensureRule(
        for bundleIdentifier: String,
        displayName: String,
        in context: ModelContext,
        defaultAllowContext: Bool = true,
        defaultAllowInsert: Bool = true
    ) throws -> AppPermissionRule {
        if let existing = try rule(for: bundleIdentifier, in: context) {
            return existing
        }

        let created = AppPermissionRule(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            allowContext: defaultAllowContext,
            allowInsert: defaultAllowInsert
        )
        context.insert(created)
        try context.save()
        return created
    }
}
