import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HTTPRequest: Sendable, Equatable {
    var method: String
    var url: URL
    var headers: [String: String] = [:]
    var body: Data?
}

struct HTTPResponse: Sendable {
    let status: Int
    let body: Data
    private let headers: [String: String]

    init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.body = body
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
    }

    /// Header names are case-insensitive.
    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// Sends one request. Throws only when there is no answer at all (offline, timeout, TLS); an error status is an answer.
protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        // The config's ETag is handled by the SDK; a URL cache would answer the 304 itself.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        return try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: urlRequest) { data, response, error in
                guard let http = response as? HTTPURLResponse, error == nil else {
                    return continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
                var headers: [String: String] = [:]
                for case let (name as String, value as String) in http.allHeaderFields {
                    headers[name] = value
                }
                continuation.resume(returning: HTTPResponse(status: http.statusCode, headers: headers, body: data ?? Data()))
            }.resume()
        }
    }
}
