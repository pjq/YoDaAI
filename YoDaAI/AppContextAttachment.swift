//
//  AppContextAttachment.swift
//  YoDaAI
//
//  App context attachment model for storing @ mentioned app context in chat messages
//

import Foundation
import SwiftData

@Model
final class AppContextAttachment: Identifiable {
    var id: UUID
    var createdAt: Date

    // App identification
    var bundleIdentifier: String  // e.g., "com.google.Chrome"
    var appName: String            // e.g., "Google Chrome"

    // Captured context
    var windowTitle: String?
    var focusedContent: String?
    var focusedRole: String?
    var isSecureField: Bool

    // Relationship
    var message: ChatMessage?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        bundleIdentifier: String,
        appName: String,
        windowTitle: String? = nil,
        focusedContent: String? = nil,
        focusedRole: String? = nil,
        isSecureField: Bool = false,
        message: ChatMessage? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.windowTitle = windowTitle
        self.focusedContent = focusedContent
        self.focusedRole = focusedRole
        self.isSecureField = isSecureField
        self.message = message
    }
}
