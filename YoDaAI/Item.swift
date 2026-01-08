//
//  Item.swift
//  YoDaAI
//
//  Created by Peng, Jianqing on 2026/1/6.
//

import Foundation
import SwiftData

@Model
final class ChatThread {
    var id: UUID
    var title: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    var messages: [ChatMessage]

    init(id: UUID = UUID(), title: String = "New Chat", createdAt: Date = Date(), messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.messages = messages
    }
}

@Model
final class ChatMessage {
    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    var id: UUID
    var createdAt: Date
    var roleRawValue: String
    var content: String

    var thread: ChatThread?

    @Relationship(deleteRule: .cascade, inverse: \ImageAttachment.message)
    var attachments: [ImageAttachment]

    @Relationship(deleteRule: .cascade, inverse: \AppContextAttachment.message)
    var appContexts: [AppContextAttachment]

    var role: Role {
        get { Role(rawValue: roleRawValue) ?? .user }
        set { roleRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        role: Role,
        content: String,
        thread: ChatThread? = nil,
        attachments: [ImageAttachment] = [],
        appContexts: [AppContextAttachment] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.roleRawValue = role.rawValue
        self.content = content
        self.thread = thread
        self.attachments = attachments
        self.appContexts = appContexts
    }
}
