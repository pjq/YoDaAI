import Foundation

struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIChatCompletionsRequest: Codable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool?
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

enum OpenAICompatibleError: Error {
    case invalidBaseURL
    case transport(Error)
    case badStatus(Int)
    case decoding(Error)
    case emptyResponse
}

final class OpenAICompatibleClient {
    private let urlSession: URLSession

    nonisolated init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func createChatCompletion(
        baseURL: String,
        apiKey: String,
        model: String,
        messages: [OpenAIChatMessage]
    ) async throws -> String {
        guard let root = URL(string: baseURL) else {
            throw OpenAICompatibleError.invalidBaseURL
        }

        let endpoint = root.appending(path: "chat/completions")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let payload = OpenAIChatCompletionsRequest(model: model, messages: messages, stream: false)
        request.httpBody = try JSONEncoder().encode(payload)

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
}
