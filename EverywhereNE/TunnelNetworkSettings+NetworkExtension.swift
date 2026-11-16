//
//  TunnelNetworkSettings+NetworkExtension.swift
//  Everywhere
//
//  Created by NodePassProject on 11/16/26.
//

import Foundation
import NetworkExtension

extension TunnelNetworkSettings {
    func makePacketTunnelSettings() -> NEPacketTunnelNetworkSettings {
        let fallback = TunnelNetworkSettings()
        let settings = NEPacketTunnelNetworkSettings(
            tunnelRemoteAddress: remoteAddress.isEmpty ? fallback.remoteAddress : remoteAddress
        )
        settings.mtu = NSNumber(value: Self.mtuRange.contains(mtu) ? mtu : fallback.mtu)
        settings.ipv4Settings = makeIPv4Settings(fallback: fallback.ipv4)
        settings.ipv6Settings = ipv6.isEnabled ? makeIPv6Settings(fallback: fallback.ipv6) : nil
        settings.dnsSettings = dns.isEnabled ? makeDNSSettings() : nil
        settings.proxySettings = proxy.isEnabled ? makeProxySettings() : nil
        return settings
    }

    // MARK: - IP

    private func makeIPv4Settings(fallback: IPv4) -> NEIPv4Settings {
        var interfaces = ipv4.addresses.compactMap { IPNetwork.parse($0, family: .v4) }
        if interfaces.isEmpty {
            interfaces = fallback.addresses.compactMap { IPNetwork.parse($0, family: .v4) }
        }
        let result = NEIPv4Settings(
            addresses: interfaces.map(\.address),
            subnetMasks: interfaces.map { IPNetwork.subnetMask(prefix: $0.prefix) }
        )
        result.includedRoutes = ipv4.includedRoutes.compactMap(Self.ipv4Route)
        result.excludedRoutes = ipv4.excludedRoutes.compactMap(Self.ipv4Route)
        return result
    }

    private func makeIPv6Settings(fallback: IPv6) -> NEIPv6Settings {
        var interfaces = ipv6.addresses.compactMap { IPNetwork.parse($0, family: .v6) }
        if interfaces.isEmpty {
            interfaces = fallback.addresses.compactMap { IPNetwork.parse($0, family: .v6) }
        }
        let result = NEIPv6Settings(
            addresses: interfaces.map(\.address),
            networkPrefixLengths: interfaces.map { NSNumber(value: $0.prefix) }
        )
        result.includedRoutes = ipv6.includedRoutes.compactMap(Self.ipv6Route)
        result.excludedRoutes = ipv6.excludedRoutes.compactMap(Self.ipv6Route)
        return result
    }

    private static func ipv4Route(_ cidr: String) -> NEIPv4Route? {
        guard let network = IPNetwork.parse(cidr, family: .v4) else { return nil }
        if network.prefix == 0 { return .default() }
        return NEIPv4Route(
            destinationAddress: network.address,
            subnetMask: IPNetwork.subnetMask(prefix: network.prefix)
        )
    }

    private static func ipv6Route(_ cidr: String) -> NEIPv6Route? {
        guard let network = IPNetwork.parse(cidr, family: .v6) else { return nil }
        if network.prefix == 0 { return .default() }
        return NEIPv6Route(
            destinationAddress: network.address,
            networkPrefixLength: NSNumber(value: network.prefix)
        )
    }

    // MARK: - DNS

    private func makeDNSSettings() -> NEDNSSettings {
        var servers = dns.servers.filter { IPNetwork.isAddress($0) }
        if servers.isEmpty { servers = Self.defaultDNSServers }

        let result: NEDNSSettings
        switch dns.transport {
        case .tls where !dns.serverName.isEmpty:
            let tls = NEDNSOverTLSSettings(servers: servers)
            tls.serverName = dns.serverName
            result = tls
        case .https where URL(string: dns.serverURL)?.scheme == "https":
            let https = NEDNSOverHTTPSSettings(servers: servers)
            https.serverURL = URL(string: dns.serverURL)
            result = https
        default:
            result = NEDNSSettings(servers: servers)
        }
        result.domainName = dns.domainName.isEmpty ? nil : dns.domainName
        result.searchDomains = dns.searchDomains.isEmpty ? nil : dns.searchDomains
        result.matchDomains = dns.matchDomains.isEmpty ? nil : dns.matchDomains
        result.matchDomainsNoSearch = dns.matchDomainsNoSearch
        return result
    }

    // MARK: - Proxy

    private func makeProxySettings() -> NEProxySettings {
        let result = NEProxySettings()
        if proxy.autoConfigurationEnabled {
            result.autoProxyConfigurationEnabled = true
            result.proxyAutoConfigurationURL = URL(string: proxy.autoConfigurationURL)
            if !proxy.autoConfigurationJavaScript.isEmpty {
                result.proxyAutoConfigurationJavaScript = proxy.autoConfigurationJavaScript
            }
        }
        if proxy.httpEnabled, !proxy.httpServer.isEmpty {
            result.httpEnabled = true
            result.httpServer = NEProxyServer(address: proxy.httpServer, port: proxy.httpPort)
        }
        if proxy.httpsEnabled, !proxy.httpsServer.isEmpty {
            result.httpsEnabled = true
            result.httpsServer = NEProxyServer(address: proxy.httpsServer, port: proxy.httpsPort)
        }
        result.excludeSimpleHostnames = proxy.excludeSimpleHostnames
        result.exceptionList = proxy.exceptionList.isEmpty ? nil : proxy.exceptionList
        result.matchDomains = proxy.matchDomains.isEmpty ? nil : proxy.matchDomains
        return result
    }
}
