//
//  PacketTunnelProvider.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import EverywhereCore
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let tunnelMTU = 1500
    private static let appGroupIdentifier = "group.com.argsment.Everywhere"

    // When the Go core fails to start, we keep the NE alive so the
    // containing app can fetch the reason via IPC. Calling
    // `completionHandler(error)` would have the system terminate the NE
    // before the app gets a chance to read it.
    private var coreError: String?

    override func startTunnel(options _: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let providerConfig = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let coreType = (providerConfig["coreType"] as? String) ?? EvcoreCoreTypeXray
        let configContent = (providerConfig["configContent"] as? String) ?? ""
        let dnsServers = Self.cleanDNS(providerConfig["dnsServers"] as? [String])

        let settings = Self.makeTunnelSettings(mtu: Self.tunnelMTU, dnsServers: dnsServers)
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else { return }
            if let error {
                completionHandler(error)
                return
            }

            let fd = TunnelFD.lookup(for: self.packetFlow)
            if fd < 0 {
                completionHandler(NSError(
                    domain: "Everywhere",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "could not obtain TUN file descriptor"]
                ))
                return
            }

            // Point the active core at its own per-core subfolder of
            // the app group's Resources/ directory before it boots, so
            // its built-in asset lookups (Xray's xray.location.asset
            // env, mihomo's $HOME/.config/mihomo, sing-box's relative
            // paths via CWD) resolve to user-injected files without
            // colliding on shared filenames like cache.db across cores.
            if let resPath = Self.resourcesPath(forCoreType: coreType) {
                var resErr: NSError?
                if !EvcoreSetResourcesPath(resPath, &resErr), let resErr {
                    NSLog("Everywhere: SetResourcesPath failed: \(resErr)")
                }
            }

            var coreErr: NSError?
            guard EvcoreStartCore(coreType, configContent, Int(fd), Self.tunnelMTU, &coreErr) else {
                self.coreError = coreErr?.localizedDescription ?? "core failed to start"
                completionHandler(nil)
                return
            }

            completionHandler(nil)
        }
    }

    override func stopTunnel(with _: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        var err: NSError?
        if !EvcoreStopAll(&err), let err {
            NSLog("Everywhere: StopAll failed: \(err)")
        }
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let json = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let type = json["type"] as? String else {
            completionHandler?(nil)
            return
        }
        switch type {
        case "core-status":
            var response: [String: Any] = ["running": coreError == nil]
            if let err = coreError { response["error"] = err }
            let data = try? JSONSerialization.data(withJSONObject: response)
            completionHandler?(data)
        default:
            completionHandler?(nil)
        }
    }

    private static func makeTunnelSettings(mtu: Int, dnsServers: [String]) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = []
        settings.ipv4Settings = ipv4

        // Mirror the IPv6 prefix the cores' TUN inbounds advertise via
        // ConfigNormalizer (fd00::1/126 — a small ULA range) so iOS
        // hands v6 packets to our utun, which the gvisor stack then
        // dispatches the same way as v4.
        let ipv6 = NEIPv6Settings(addresses: ["fd00::1"], networkPrefixLengths: [126])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        ipv6.excludedRoutes = []
        settings.ipv6Settings = ipv6

        settings.dnsSettings = NEDNSSettings(servers: dnsServers)
        settings.mtu = NSNumber(value: mtu)
        return settings
    }

    private static func cleanDNS(_ raw: [String]?) -> [String] {
        let trimmed = (raw ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return trimmed.isEmpty ? ["1.1.1.1", "8.8.8.8"] : trimmed
    }

    private static func resourcesPath(forCoreType coreType: String) -> String? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return nil }
        let url = container
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(coreType, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
