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
        let data = try await sendJSONRequest(
            baseURL: baseURL,
            apiKey: apiKey,
            path: "chat/completions",
            method: "POST",
            body: OpenAIChatCompletionsRequest(model: model, messages: messages, stream: false)
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
