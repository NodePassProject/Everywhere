//
//  TunnelNetworkSettings.swift
//  Everywhere
//
//  Created by NodePassProject on 11/16/26.
//

import Darwin
import Foundation

nonisolated struct TunnelNetworkSettings: Codable, Equatable, Sendable {
    static let mtuRange = 1280...9000
    static let defaultDNSServers = ["1.1.1.1", "8.8.8.8"]

    var remoteAddress = "127.0.0.1"
    var mtu = 1500
    var ipv4 = IPv4()
    var ipv6 = IPv6()
    var dns = DNS()
    var proxy = Proxy()

    var coreAddresses: [String] {
        ipv4.addresses + (ipv6.isEnabled ? ipv6.addresses : [])
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TunnelNetworkSettings()
        remoteAddress = container.value(.remoteAddress, default: fallback.remoteAddress)
        mtu = container.value(.mtu, default: fallback.mtu)
        ipv4 = container.value(.ipv4, default: fallback.ipv4)
        ipv6 = container.value(.ipv6, default: fallback.ipv6)
        dns = container.value(.dns, default: fallback.dns)
        proxy = container.value(.proxy, default: fallback.proxy)
    }

    // MARK: - IPv4

    struct IPv4: Codable, Equatable, Sendable {
        var addresses = ["198.18.0.1/16"]
        var includedRoutes = ["0.0.0.0/0"]
        var excludedRoutes: [String] = []

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = IPv4()
            addresses = container.value(.addresses, default: fallback.addresses)
            includedRoutes = container.value(.includedRoutes, default: fallback.includedRoutes)
            excludedRoutes = container.value(.excludedRoutes, default: fallback.excludedRoutes)
        }
    }

    // MARK: - IPv6

    struct IPv6: Codable, Equatable, Sendable {
        var isEnabled = true
        var addresses = ["fd00::1/126"]
        var includedRoutes = ["::/0"]
        var excludedRoutes: [String] = []

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = IPv6()
            isEnabled = container.value(.isEnabled, default: fallback.isEnabled)
            addresses = container.value(.addresses, default: fallback.addresses)
            includedRoutes = container.value(.includedRoutes, default: fallback.includedRoutes)
            excludedRoutes = container.value(.excludedRoutes, default: fallback.excludedRoutes)
        }
    }

    // MARK: - DNS

    enum DNSTransport: String, Codable, CaseIterable, Identifiable, Sendable {
        case cleartext, tls, https

        var id: String { rawValue }
    }

    struct DNS: Codable, Equatable, Sendable {
        var isEnabled = true
        var transport = DNSTransport.cleartext
        var servers = TunnelNetworkSettings.defaultDNSServers
        var serverName = ""
        var serverURL = ""
        var domainName = ""
        var searchDomains: [String] = []
        var matchDomains: [String] = []
        var matchDomainsNoSearch = false

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = DNS()
            isEnabled = container.value(.isEnabled, default: fallback.isEnabled)
            transport = container.value(.transport, default: fallback.transport)
            servers = container.value(.servers, default: fallback.servers)
            serverName = container.value(.serverName, default: fallback.serverName)
            serverURL = container.value(.serverURL, default: fallback.serverURL)
            domainName = container.value(.domainName, default: fallback.domainName)
            searchDomains = container.value(.searchDomains, default: fallback.searchDomains)
            matchDomains = container.value(.matchDomains, default: fallback.matchDomains)
            matchDomainsNoSearch = container.value(.matchDomainsNoSearch, default: fallback.matchDomainsNoSearch)
        }
    }

    // MARK: - Proxy

    struct Proxy: Codable, Equatable, Sendable {
        var isEnabled = false
        var autoConfigurationEnabled = false
        var autoConfigurationURL = ""
        var autoConfigurationJavaScript = ""
        var httpEnabled = false
        var httpServer = "127.0.0.1"
        var httpPort = 8080
        var httpsEnabled = false
        var httpsServer = "127.0.0.1"
        var httpsPort = 8080
        var excludeSimpleHostnames = false
        var exceptionList: [String] = []
        var matchDomains: [String] = []

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let fallback = Proxy()
            isEnabled = container.value(.isEnabled, default: fallback.isEnabled)
            autoConfigurationEnabled = container.value(.autoConfigurationEnabled, default: fallback.autoConfigurationEnabled)
            autoConfigurationURL = container.value(.autoConfigurationURL, default: fallback.autoConfigurationURL)
            autoConfigurationJavaScript = container.value(.autoConfigurationJavaScript, default: fallback.autoConfigurationJavaScript)
            httpEnabled = container.value(.httpEnabled, default: fallback.httpEnabled)
            httpServer = container.value(.httpServer, default: fallback.httpServer)
            httpPort = container.value(.httpPort, default: fallback.httpPort)
            httpsEnabled = container.value(.httpsEnabled, default: fallback.httpsEnabled)
            httpsServer = container.value(.httpsServer, default: fallback.httpsServer)
            httpsPort = container.value(.httpsPort, default: fallback.httpsPort)
            excludeSimpleHostnames = container.value(.excludeSimpleHostnames, default: fallback.excludeSimpleHostnames)
            exceptionList = container.value(.exceptionList, default: fallback.exceptionList)
            matchDomains = container.value(.matchDomains, default: fallback.matchDomains)
        }
    }
}

nonisolated private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, default fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

// MARK: - Validation

nonisolated enum IPFamily: Sendable {
    case v4, v6

    var maxPrefix: Int { self == .v4 ? 32 : 128 }
}

nonisolated enum IPNetwork {
    static func isAddress(_ string: String, family: IPFamily) -> Bool {
        switch family {
        case .v4:
            var address = in_addr()
            return inet_pton(AF_INET, string, &address) == 1
        case .v6:
            var address = in6_addr()
            return inet_pton(AF_INET6, string, &address) == 1
        }
    }

    static func isAddress(_ string: String) -> Bool {
        isAddress(string, family: .v4) || isAddress(string, family: .v6)
    }

    static func isHostname(_ string: String) -> Bool {
        !string.isEmpty && !string.contains(where: \.isWhitespace) && !string.contains("/")
    }

    static func parse(_ cidr: String, family: IPFamily) -> (address: String, prefix: Int)? {
        let parts = cidr.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              (0...family.maxPrefix).contains(prefix),
              isAddress(String(parts[0]), family: family) else { return nil }
        return (String(parts[0]), prefix)
    }

    static func isInterfaceAddress(_ cidr: String, family: IPFamily) -> Bool {
        guard let parsed = parse(cidr, family: family) else { return false }
        return parsed.prefix > 0
    }

    static func subnetMask(prefix: Int) -> String {
        let bits: UInt32 = prefix <= 0 ? 0 : ~UInt32(0) << UInt32(32 - min(prefix, 32))
        return [24, 16, 8, 0].map { String((bits >> UInt32($0)) & 0xff) }.joined(separator: ".")
    }
}
