//
//  ClashAPI.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import Foundation

nonisolated final class ClashAPI: Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        configuration.connectionProxyDictionary = [:]
        session = URLSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    // MARK: Requests

    private func makeRequest(
        scheme: String,
        path: String,
        query: [URLQueryItem]
    ) throws -> URLRequest {
        guard var components = URLComponents(string: "\(scheme)://\(EVCore.controllerAddress)") else {
            throw DashboardError.invalidResponse
        }
        components.percentEncodedPath = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw DashboardError.invalidResponse }
        var request = URLRequest(url: url)
        if let secret = EVCore.getControllerSecret() {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static func segment(_ name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }

    @concurrent
    @discardableResult
    func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: String]? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> Data {
        var request = try makeRequest(scheme: "http", path: path, query: query)
        request.httpMethod = method
        if let timeout { request.timeoutInterval = timeout }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DashboardError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ClashMessage.self, from: data))?.message ?? ""
            throw DashboardError.http(status: http.statusCode, message: message)
        }
        return data
    }

    @concurrent
    func get<T: Decodable & Sendable>(
        _ type: T.Type = T.self,
        _ path: String,
        query: [URLQueryItem] = [],
        timeout: TimeInterval? = nil
    ) async throws -> T {
        let data = try await send("GET", path, query: query, timeout: timeout)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DashboardError.invalidResponse
        }
    }

    // MARK: Streams

    func stream<T: Decodable & Sendable>(
        _ type: T.Type = T.self,
        _ path: String,
        query: [URLQueryItem] = []
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let request: URLRequest
            do {
                request = try makeRequest(scheme: "ws", path: path, query: query)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            let socket = session.webSocketTask(with: request)
            socket.maximumMessageSize = 32 * 1024 * 1024
            socket.resume()

            let reader = Task {
                let decoder = JSONDecoder()
                do {
                    while !Task.isCancelled {
                        let data: Data
                        switch try await socket.receive() {
                        case .data(let payload): data = payload
                        case .string(let text): data = Data(text.utf8)
                        @unknown default: continue
                        }
                        continuation.yield(try decoder.decode(T.self, from: data))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                reader.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}

// MARK: - Wire types

nonisolated struct ClashMessage: Decodable, Sendable {
    let message: String
}

nonisolated struct ClashVersion: Decodable, Sendable {
    let version: String
    let premium: Bool?
}

nonisolated struct ClashDelayHistory: Decodable, Sendable {
    let delay: Int
}

nonisolated struct ClashProxy: Decodable, Sendable {
    let name: String
    let type: String
    let udp: Bool?
    let history: [ClashDelayHistory]?
    let now: String?
    let all: [String]?
    let fixed: String?
    let hidden: Bool?
    let testUrl: String?
}

nonisolated struct ClashProxies: Decodable, Sendable {
    let proxies: [String: ClashProxy]
}

nonisolated struct ClashDelay: Decodable, Sendable {
    let delay: Int
}

nonisolated struct ClashProxyProvider: Decodable, Sendable {
    let name: String
    let vehicleType: String
    let proxies: [ClashProxy]?
    let updatedAt: String?
    let subscriptionInfo: Subscription?

    struct Subscription: Decodable, Sendable {
        let Upload: Int64?
        let Download: Int64?
        let Total: Int64?
        let Expire: Int64?
    }
}

nonisolated struct ClashProxyProviders: Decodable, Sendable {
    let providers: [String: ClashProxyProvider]
}

nonisolated struct ClashRuleProvider: Decodable, Sendable {
    let name: String
    let behavior: String?
    let format: String?
    let vehicleType: String?
    let ruleCount: Int?
    let updatedAt: String?
}

nonisolated struct ClashRuleProviders: Decodable, Sendable {
    let providers: [String: ClashRuleProvider]
}

nonisolated struct ClashTraffic: Decodable, Sendable {
    let up: Int64
    let down: Int64
    let upTotal: Int64?
    let downTotal: Int64?
}

nonisolated struct ClashConnections: Decodable, Sendable {
    let downloadTotal: Int64
    let uploadTotal: Int64
    let connections: [Connection]?

    struct Connection: Decodable, Sendable {
        let id: String
        let metadata: Metadata
        let upload: Int64
        let download: Int64
        let start: String
        let chains: [String]?
        let rule: String?
        let rulePayload: String?
    }

    struct Metadata: Decodable, Sendable {
        let network: String?
        let type: String?
        let sourceIP: String?
        let sourcePort: String?
        let destinationIP: String?
        let destinationPort: String?
        let host: String?
        let dnsMode: String?
        let process: String?
        let processPath: String?
        let sniffHost: String?
        let remoteDestination: String?
    }
}

nonisolated struct ClashLog: Decodable, Sendable {
    let type: String
    let payload: String
}

nonisolated struct ClashRules: Decodable, Sendable {
    let rules: [Rule]?

    struct Rule: Decodable, Sendable {
        let type: String
        let payload: String
        let proxy: String
    }
}

nonisolated struct ClashConfigs: Decodable, Sendable {
    let mode: String?
    let modeList: [String]?

    enum CodingKeys: String, CodingKey {
        case mode
        case modeList = "mode-list"
    }
}

nonisolated struct ClashDNSResponse: Decodable, Sendable {
    let Status: Int?
    let Answer: [Record]?

    struct Record: Decodable, Sendable {
        let name: String
        let type: Int
        let TTL: Int
        let data: String
    }
}
