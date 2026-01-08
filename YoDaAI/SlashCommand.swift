//
//  SlashCommand.swift
//  YoDaAI
//
//  Slash command system for chat interface
//

import Foundation

// MARK: - Slash Command Definition

/// Available slash commands in the chat interface
enum SlashCommand: String, CaseIterable, Identifiable {
    case help = "help"
    case clear = "clear"
    case new = "new"
    case models = "models"
    case settings = "settings"
    case copy = "copy"

    var id: String { rawValue }

    /// Display name shown in autocomplete
    var displayName: String {
        "/\(rawValue)"
    }

    /// Description shown in autocomplete and help
    var description: String {
        switch self {
        case .help:
            return "Show available commands"
        case .clear:
            return "Clear current conversation"
        case .new:
            return "Create a new chat"
        case .models:
            return "Show model selector"
        case .settings:
            return "Open settings"
        case .copy:
            return "Copy conversation to clipboard"
        }
    }

    /// SF Symbol icon for the command
    var icon: String {
        switch self {
        case .help:
            return "questionmark.circle"
        case .clear:
            return "trash"
        case .new:
            return "plus.message"
        case .models:
            return "cpu"
        case .settings:
            return "gear"
        case .copy:
            return "doc.on.doc"
        }
    }
}

// MARK: - Slash Command Parser

struct SlashCommandParser {
    /// Parse text to detect if it's a slash command
    /// Returns the command if found, or nil if not a command
    static func parse(_ text: String) -> SlashCommand? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Must start with /
        guard trimmed.hasPrefix("/") else { return nil }

        // Extract command (everything after /)
        let commandText = String(trimmed.dropFirst()).lowercased()

        // Match against known commands
        return SlashCommand.allCases.first { $0.rawValue == commandText }
    }

    /// Check if text starts with / to show autocomplete
    static func shouldShowAutocomplete(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/") && trimmed.count >= 1
    }

    /// Filter commands based on partial input
    /// e.g., "/he" returns [.help]
    static func filterCommands(for text: String) -> [SlashCommand] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("/") else { return [] }

        let searchText = String(trimmed.dropFirst()).lowercased()

        // If just "/", show all commands
        if searchText.isEmpty {
            return SlashCommand.allCases
        }

        // Filter by prefix match
        return SlashCommand.allCases.filter { $0.rawValue.hasPrefix(searchText) }
    }
}
