//
//  Project.swift
//  YoDaAI
//
//  A Project scopes chats to a working directory, so the pi agent runs with the
//  right cwd (like Codex / Claude Code desktop). Chats belong to a project;
//  chats with no project are "loose" chats shown under a general section.
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    /// Absolute path to the project's working directory (pi runs with this cwd).
    var workingDirectory: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \ChatThread.project)
    var threads: [ChatThread]

    init(id: UUID = UUID(),
         name: String,
         workingDirectory: String,
         createdAt: Date = Date(),
         threads: [ChatThread] = []) {
        self.id = id
        self.name = name
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.threads = threads
    }

    /// Display name derived from the directory if no explicit name.
    var displayName: String {
        name.isEmpty ? (URL(fileURLWithPath: workingDirectory).lastPathComponent) : name
    }
}
