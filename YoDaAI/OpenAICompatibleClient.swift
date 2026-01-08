import Foundation

// MARK: - Message Content Types (Vision API Support)

/// Content part for multimodal messages (text or image)
struct OpenAIChatMessageContent: Codable {
    let type: String
    let text: String?
    let imageUrl: ImageUrlData?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }

    struct ImageUrlData: Codable {
        let url: String
        let detail: String?
    }

    /// Create text content part
    static func text(_ content: String) -> OpenAIChatMessageContent {
        OpenAIChatMessageContent(type: "text", text: content, imageUrl: nil)
    }

    /// Create image URL content part
    static func imageUrl(url: String, detail: String? = "auto") -> OpenAIChatMessageContent {
        OpenAIChatMessageContent(
            type: "image_url",
            text: nil,
            imageUrl: ImageUrlData(url: url, detail: detail)
        )
    }
}

/// Message content that can be either a simple string or an array of content parts
enum OpenAIChatMessageContentValue: Codable {
    case string(String)
    case array([OpenAIChatMessageContent])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([OpenAIChatMessageContent].self) {
            self = .array(array)
        } else {
            throw DecodingError.typeMismatch(
                OpenAIChatMessageContentValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid content type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        }
    }
}

/// Chat message supporting both text-only and multimodal content
struct OpenAIChatMessage: Codable {
    let role: String
    let content: OpenAIChatMessageContentValue

    /// Create text-only message (backward compatible)
    init(role: String, content: String) {
        self.role = role
        self.content = .string(content)
    }

    /// Create multimodal message with content parts
    init(role: String, contentParts: [OpenAIChatMessageContent]) {
        self.role = role
        self.content = .array(contentParts)
    }
}

struct OpenAIChatCompletionsRequest: Codable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool?
    let temperature: Double?
    let maxTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }
    
    init(model: String, messages: [OpenAIChatMessage], stream: Bool? = nil, temperature: Double? = nil, maxTokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

struct OpenAIChatCompletionsResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }

        let index: Int
        let message: Message
    }

    let id: String?
    let choices: [Choice]
}

// Streaming response structure
struct OpenAIChatCompletionsStreamResponse: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let role: String?
            let content: String?
        }
        
        let index: Int
        let delta: Delta
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }
    
    let id: String?
    let choices: [Choice]
}

struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
}

struct OpenAIModel: Codable, Hashable, Identifiable {
    let id: String
    let created: Int?
    let object: String?
    let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case created
        case object
        case ownedBy = "owned_by"
    }
}

enum OpenAICompatibleError: Error {
    case invalidBaseURL
    case notConfigured
    case transport(Error)
    case badStatus(Int)
    case decoding(Error)
    case emptyResponse
    case streamingError(String)
}

extension OpenAICompatibleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid server URL. Please check your provider settings."
        case .notConfigured:
            return "Provider is not configured. Please add an API key in Settings."
        case .transport:
            return "Network error. Please check your connection and try again."
        case .badStatus(let status):
            switch status {
            case 401:
                return "Unauthorized (401). Please verify your API key."
            case 403:
                return "Forbidden (403). Your API key may not have access to this model."
            case 404:
                return "Endpoint not found (404). Please check the provider base URL."
            case 429:
                return "Rate limited (429). Please wait and try again."
            case 500...599:
                return "Server error (\(status)). Please try again later."
            default:
                return "Unexpected server response (\(status))."
            }
        case .decoding:
            return "Could not read the server response. Please try again."
        case .emptyResponse:
            return "The model returned an empty response."
        case .streamingError(let message):
            return message
        }
    }
}

final class OpenAICompatibleClient: @unchecked Sendable {
    private let urlSession: URLSession

    nonisolated init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Convert image data to base64 data URL for Vision API
    static func encodeImageToDataURL(data: Data, mimeType: String) -> String {
        let base64String = data.base64EncodedString()
        return "data:\(mimeType);base64,\(base64String)"
    }

    /// Non-streaming chat completion (kept for compatibility)
    func createChatCompletion(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [OpenAIChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> String {
        let data = try await sendJSONRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            path: "chat/completions",
            method: "POST",
            body: OpenAIChatCompletionsRequest(model: model, messages: messages, stream: false, temperature: temperature, maxTokens: maxTokens)
        )

        do {
            let decoded = try JSONDecoder().decode(OpenAIChatCompletionsResponse.self, from: data)
            guard let first = decoded.choices.first else {
                throw OpenAICompatibleError.emptyResponse
            }
            return first.message.content
        } catch {
            throw OpenAICompatibleError.decoding(error)
        }
    }
    
    /// Streaming chat completion - returns an AsyncThrowingStream of content deltas
    func createChatCompletionStream(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [OpenAIChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let root = URL(string: baseURL) else {
                        throw OpenAICompatibleError.invalidBaseURL
                    }
                    
                    let endpoint = root.appending(path: "chat/completions")
                    
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    
                    let body = OpenAIChatCompletionsRequest(model: model, messages: messages, stream: true, temperature: temperature, maxTokens: maxTokens)
                    request.httpBody = try JSONEncoder().encode(body)
                    
                    let (bytes, response) = try await self.urlSession.bytes(for: request)
                    
                    let http = response as? HTTPURLResponse
                    let status = http?.statusCode ?? -1
                    guard (200..<300).contains(status) else {
                        throw OpenAICompatibleError.badStatus(status)
                    }
                    
                    // Process SSE stream
                    var lineCount = 0
                    var yieldCount = 0
                    for try await line in bytes.lines {
                        lineCount += 1
                        // SSE format: "data: {json}" or "data: [DONE]"
                        guard line.hasPrefix("data: ") else {
                            if lineCount <= 5 {
                                print("[OpenAIStream] Non-data line \(lineCount): \(line.prefix(100))")
                            }
                            continue
                        }

                        let jsonString = String(line.dropFirst(6))

                        if jsonString == "[DONE]" {
                            print("[OpenAIStream] Received [DONE], yielded \(yieldCount) chunks")
                            break
                        }

                        guard let jsonData = jsonString.data(using: .utf8) else {
                            print("[OpenAIStream] Failed to convert to data: \(jsonString.prefix(100))")
                            continue
                        }

                        do {
                            let chunk = try JSONDecoder().decode(OpenAIChatCompletionsStreamResponse.self, from: jsonData)
                            if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                                yieldCount += 1
                                continuation.yield(content)
                            }
                        } catch {
                            // Skip malformed chunks but continue streaming
                            if lineCount <= 5 {
                                print("[OpenAIStream] Decode error on line \(lineCount): \(error)")
                                print("[OpenAIStream] JSON was: \(jsonString.prefix(200))")
                            }
                            continue
                        }
                    }
                    print("[OpenAIStream] Stream ended. Lines: \(lineCount), Yielded: \(yieldCount))")
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func listModels(
        baseURL: String,
        apiKey: String
    ) async throws -> [OpenAIModel] {
        let data = try await sendJSONRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            path: "models",
            method: "GET",
            body: Optional<Int>.none
        )

        do {
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            return decoded.data.sorted { $0.id < $1.id }
        } catch {
            throw OpenAICompatibleError.decoding(error)
        }
    }

    private func sendJSONRequest<Body: Encodable>(
        baseURL: String,
        apiKey: String,
        path: String,
        method: String,
        body: Body?
    ) async throws -> Data {
        guard let root = URL(string: baseURL) else {
            throw OpenAICompatibleError.invalidBaseURL
        }

        let endpoint = root.appending(path: path)

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw OpenAICompatibleError.transport(error)
        }

        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw OpenAICompatibleError.badStatus(status)
        }

        return data
    }
}
