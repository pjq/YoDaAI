import Foundation
import SwiftData

// MARK: - Export Bundle (top-level)

struct ExportBundle: Codable {
    let version: Int
    let exportDate: Date
    let appVersion: String
    let threads: [ThreadExport]
    let projects: [ProjectExport]?          // added in v2; optional for v1 imports
    let providers: [ProviderExport]
    let mcpServers: [MCPServerExport]
    let permissions: [PermissionExport]
    let settings: SettingsExport
}

// MARK: - Project DTO

struct ProjectExport: Codable {
    let id: UUID
    let name: String
    let workingDirectory: String
    let createdAt: Date
}

// MARK: - Thread & Message DTOs

struct ThreadExport: Codable {
    let id: UUID
    let title: String
    let createdAt: Date
    let projectID: UUID?                    // link to owning project (v2)
    let piSessionPath: String?              // pi session backing this thread (v2)
    let messages: [MessageExport]
}

struct MessageExport: Codable {
    let id: UUID
    let createdAt: Date
    let roleRawValue: String
    let content: String
    let appContexts: [AppContextExport]
    let images: [ImageExport]?             // image attachments w/ file bytes (v2)
}

// MARK: - Image Attachment DTO

struct ImageExport: Codable {
    let id: UUID
    let createdAt: Date
    let fileName: String
    let filePath: String
    let mimeType: String
    let fileSize: Int
    let width: Int?
    let height: Int?
    let dataBase64: String?                // file bytes; nil if the file was missing
}

struct AppContextExport: Codable {
    let id: UUID
    let createdAt: Date
    let bundleIdentifier: String
    let appName: String
    let windowTitle: String?
    let focusedContent: String?
    let focusedRole: String?
    let isSecureField: Bool
}

// MARK: - Provider DTO

struct ProviderExport: Codable {
    let id: UUID
    let name: String
    let baseURL: String
    let apiKey: String
    let selectedModel: String
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - MCP Server DTO

struct MCPServerExport: Codable {
    let id: UUID
    let name: String
    let endpoint: String
    let transportRawValue: String
    let isEnabled: Bool
    let apiKey: String
    let customHeadersJSON: String
    let connectionTimeout: Int
    let toolCallTimeout: Int?
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Permission DTO

struct PermissionExport: Codable {
    let id: UUID
    let bundleIdentifier: String
    let displayName: String
    let allowContext: Bool
    let allowInsert: Bool
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Settings DTO

struct SettingsExport: Codable {
    let temperature: Double
    let maxTokens: Int
    let maxMessageCount: Int
    let systemPrompt: String
    let useSystemPrompt: Bool
    let alwaysAttachAppContext: Bool
    let enableMarkdown: Bool
    let appearanceMode: Int
    let showTimestamps: Bool
    let mcpEnabled: Bool
    let textScale: Double
    let usePiAgent: Bool?                   // added in v2; optional for v1 imports
}

// MARK: - Data Exporter

@MainActor
enum DataExporter {

    static func exportAll(context: ModelContext) async throws -> Data {
        // Fetch all models
        let threads = try context.fetch(FetchDescriptor<ChatThread>(sortBy: [SortDescriptor(\.createdAt)]))
        let projects = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)]))
        let providers = try context.fetch(FetchDescriptor<LLMProvider>(sortBy: [SortDescriptor(\.createdAt)]))
        let mcpServers = try context.fetch(FetchDescriptor<MCPServer>(sortBy: [SortDescriptor(\.createdAt)]))
        let permissions = try context.fetch(FetchDescriptor<AppPermissionRule>(sortBy: [SortDescriptor(\.createdAt)]))

        let projectExports = projects.map { p in
            ProjectExport(id: p.id, name: p.name, workingDirectory: p.workingDirectory, createdAt: p.createdAt)
        }

        // Map to DTOs (async: image bytes are read from disk)
        var threadExports: [ThreadExport] = []
        for thread in threads {
            let sortedMessages = thread.messages.sorted { $0.createdAt < $1.createdAt }
            var messageExports: [MessageExport] = []
            for msg in sortedMessages {
                let contextExports = msg.appContexts.map { ctx in
                    AppContextExport(
                        id: ctx.id, createdAt: ctx.createdAt,
                        bundleIdentifier: ctx.bundleIdentifier, appName: ctx.appName,
                        windowTitle: ctx.windowTitle, focusedContent: ctx.focusedContent,
                        focusedRole: ctx.focusedRole, isSecureField: ctx.isSecureField
                    )
                }
                var imageExports: [ImageExport] = []
                for img in msg.attachments {
                    // Read the file bytes so images survive export/import. If the
                    // file is missing, still export the metadata with nil data.
                    let base64 = try? await ImageStorageService.shared.loadImage(filePath: img.filePath).base64EncodedString()
                    imageExports.append(ImageExport(
                        id: img.id, createdAt: img.createdAt,
                        fileName: img.fileName, filePath: img.filePath,
                        mimeType: img.mimeType, fileSize: img.fileSize,
                        width: img.width, height: img.height,
                        dataBase64: base64))
                }
                messageExports.append(MessageExport(
                    id: msg.id, createdAt: msg.createdAt,
                    roleRawValue: msg.roleRawValue, content: msg.content,
                    appContexts: contextExports,
                    images: imageExports.isEmpty ? nil : imageExports))
            }
            threadExports.append(ThreadExport(
                id: thread.id, title: thread.title, createdAt: thread.createdAt,
                projectID: thread.project?.id, piSessionPath: thread.piSessionPath,
                messages: messageExports))
        }

        let providerExports = providers.map { p in
            ProviderExport(
                id: p.id, name: p.name, baseURL: p.baseURL, apiKey: p.apiKey,
                selectedModel: p.selectedModel, isDefault: p.isDefault,
                createdAt: p.createdAt, updatedAt: p.updatedAt
            )
        }

        let mcpExports = mcpServers.map { s in
            MCPServerExport(
                id: s.id, name: s.name, endpoint: s.endpoint,
                transportRawValue: s.transportRawValue, isEnabled: s.isEnabled,
                apiKey: s.apiKey, customHeadersJSON: s.customHeadersJSON,
                connectionTimeout: s.connectionTimeout,
                toolCallTimeout: s.toolCallTimeout,
                createdAt: s.createdAt, updatedAt: s.updatedAt
            )
        }

        let permExports = permissions.map { p in
            PermissionExport(
                id: p.id, bundleIdentifier: p.bundleIdentifier, displayName: p.displayName,
                allowContext: p.allowContext, allowInsert: p.allowInsert,
                createdAt: p.createdAt, updatedAt: p.updatedAt
            )
        }

        // Read UserDefaults settings
        let ud = UserDefaults.standard
        let settingsExport = SettingsExport(
            temperature: ud.object(forKey: "llm_temperature") as? Double ?? 1.0,
            maxTokens: ud.object(forKey: "llm_maxTokens") as? Int ?? 0,
            maxMessageCount: ud.object(forKey: "llm_maxMessageCount") as? Int ?? 20,
            systemPrompt: ud.string(forKey: "llm_systemPrompt") ?? "You are a helpful assistant.",
            useSystemPrompt: ud.object(forKey: "llm_useSystemPrompt") as? Bool ?? true,
            alwaysAttachAppContext: ud.object(forKey: "llm_alwaysAttachAppContext") as? Bool ?? true,
            enableMarkdown: ud.object(forKey: "llm_enableMarkdown") as? Bool ?? true,
            appearanceMode: ud.integer(forKey: "app_appearanceMode"),
            showTimestamps: ud.object(forKey: "app_showTimestamps") as? Bool ?? false,
            mcpEnabled: ud.object(forKey: "mcp_enabled") as? Bool ?? false,
            textScale: ud.object(forKey: "app_text_scale") as? Double ?? 1.0,
            usePiAgent: ud.object(forKey: "llm_usePiAgent") as? Bool ?? false
        )

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        let bundle = ExportBundle(
            version: 2,
            exportDate: Date(),
            appVersion: appVersion,
            threads: threadExports,
            projects: projectExports,
            providers: providerExports,
            mcpServers: mcpExports,
            permissions: permExports,
            settings: settingsExport
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    static func importAll(from data: Data, context: ModelContext) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        // Delete all existing data (threads cascade-delete messages, attachments, contexts)
        try context.delete(model: ChatThread.self)
        try context.delete(model: ChatMessage.self)
        try context.delete(model: ImageAttachment.self)
        try context.delete(model: AppContextAttachment.self)
        try context.delete(model: Project.self)
        try context.delete(model: LLMProvider.self)
        try context.delete(model: MCPServer.self)
        try context.delete(model: AppPermissionRule.self)

        // Import projects first so threads can link to them.
        var projectsByID: [UUID: Project] = [:]
        for p in bundle.projects ?? [] {
            let project = Project(id: p.id, name: p.name, workingDirectory: p.workingDirectory, createdAt: p.createdAt)
            context.insert(project)
            projectsByID[p.id] = project
        }

        // Import threads with messages, app contexts, and image attachments.
        for threadExport in bundle.threads {
            let thread = ChatThread(
                id: threadExport.id, title: threadExport.title, createdAt: threadExport.createdAt,
                project: threadExport.projectID.flatMap { projectsByID[$0] },
                piSessionPath: threadExport.piSessionPath
            )
            context.insert(thread)

            for msgExport in threadExport.messages {
                let role = ChatMessage.Role(rawValue: msgExport.roleRawValue) ?? .user
                let message = ChatMessage(
                    id: msgExport.id, createdAt: msgExport.createdAt,
                    role: role, content: msgExport.content, thread: thread
                )
                context.insert(message)

                for ctxExport in msgExport.appContexts {
                    let appCtx = AppContextAttachment(
                        id: ctxExport.id, createdAt: ctxExport.createdAt,
                        bundleIdentifier: ctxExport.bundleIdentifier, appName: ctxExport.appName,
                        windowTitle: ctxExport.windowTitle, focusedContent: ctxExport.focusedContent,
                        focusedRole: ctxExport.focusedRole, isSecureField: ctxExport.isSecureField,
                        message: message
                    )
                    context.insert(appCtx)
                }

                for imgExport in msgExport.images ?? [] {
                    // Restore the image file bytes to disk (same filename) so the
                    // filePath reference stays valid.
                    if let b64 = imgExport.dataBase64, let bytes = Data(base64Encoded: b64) {
                        try? await ImageStorageService.shared.writeImage(data: bytes, fileName: imgExport.fileName)
                    }
                    let img = ImageAttachment(
                        id: imgExport.id, createdAt: imgExport.createdAt,
                        fileName: imgExport.fileName, filePath: imgExport.filePath,
                        mimeType: imgExport.mimeType, fileSize: imgExport.fileSize,
                        width: imgExport.width, height: imgExport.height,
                        message: message
                    )
                    context.insert(img)
                }
            }
        }

        // Import providers
        for p in bundle.providers {
            let provider = LLMProvider(
                id: p.id, name: p.name, baseURL: p.baseURL, apiKey: p.apiKey,
                selectedModel: p.selectedModel, isDefault: p.isDefault,
                createdAt: p.createdAt, updatedAt: p.updatedAt
            )
            context.insert(provider)
        }

        // Import MCP servers
        for s in bundle.mcpServers {
            let server = MCPServer(name: s.name, endpoint: s.endpoint)
            server.id = s.id
            server.transportRawValue = s.transportRawValue
            server.isEnabled = s.isEnabled
            server.apiKey = s.apiKey
            server.customHeadersJSON = s.customHeadersJSON
            server.connectionTimeout = s.connectionTimeout
            server.toolCallTimeout = s.toolCallTimeout ?? 300
            server.createdAt = s.createdAt
            server.updatedAt = s.updatedAt
            context.insert(server)
        }

        // Import permissions
        for p in bundle.permissions {
            let rule = AppPermissionRule(
                id: p.id, bundleIdentifier: p.bundleIdentifier, displayName: p.displayName,
                allowContext: p.allowContext, allowInsert: p.allowInsert,
                createdAt: p.createdAt, updatedAt: p.updatedAt
            )
            context.insert(rule)
        }

        // Save all SwiftData changes
        try context.save()

        // Restore UserDefaults settings
        let settings = bundle.settings
        let ud = UserDefaults.standard
        ud.set(settings.temperature, forKey: "llm_temperature")
        ud.set(settings.maxTokens, forKey: "llm_maxTokens")
        ud.set(settings.maxMessageCount, forKey: "llm_maxMessageCount")
        ud.set(settings.systemPrompt, forKey: "llm_systemPrompt")
        ud.set(settings.useSystemPrompt, forKey: "llm_useSystemPrompt")
        ud.set(settings.alwaysAttachAppContext, forKey: "llm_alwaysAttachAppContext")
        ud.set(settings.enableMarkdown, forKey: "llm_enableMarkdown")
        ud.set(settings.appearanceMode, forKey: "app_appearanceMode")
        ud.set(settings.showTimestamps, forKey: "app_showTimestamps")
        ud.set(settings.mcpEnabled, forKey: "mcp_enabled")
        ud.set(settings.textScale, forKey: "app_text_scale")
        ud.set(settings.usePiAgent ?? false, forKey: "llm_usePiAgent")

        // Reload LLMSettings singleton from UserDefaults
        let llm = LLMSettings.shared
        llm.temperature = settings.temperature
        llm.maxTokens = settings.maxTokens
        llm.maxMessageCount = settings.maxMessageCount
        llm.systemPrompt = settings.systemPrompt
        llm.useSystemPrompt = settings.useSystemPrompt
        llm.alwaysAttachAppContext = settings.alwaysAttachAppContext
        llm.enableMarkdown = settings.enableMarkdown
        llm.appearanceMode = AppearanceMode(rawValue: settings.appearanceMode) ?? .system
        llm.showTimestamps = settings.showTimestamps
        llm.usePiAgent = settings.usePiAgent ?? false

        // Reload text scale
        AppScaleManager.shared.scale = CGFloat(settings.textScale)
    }
}
