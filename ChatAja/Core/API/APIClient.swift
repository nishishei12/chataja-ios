import Foundation

// MARK: - API Client

final class APIClient {
    static let shared = APIClient()
    private init() {}

    private let baseURL = "https://chat-anon-roan.vercel.app/api"

    private func headers() -> [String: String] {
        var h: [String: String] = ["Content-Type": "application/json"]
        if let token = AuthManager.shared.idToken {
            h["Authorization"] = "Bearer \(token)"
        }
        return h
    }

    func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(string: baseURL + path)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        headers().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = "POST"
        headers().forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            throw APIError.http(code)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum APIError: Error {
    case http(Int)
    case decoding
}

// MARK: - Response Wrappers

struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
}
