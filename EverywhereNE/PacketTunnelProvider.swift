//
//  PacketTunnelProvider.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import CoreData
import EverywhereCore
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let tunnelMTU = 1500

    // When the Go core fails to start, we keep the NE alive so the
    // containing app can fetch the reason via IPC. Calling
    // `completionHandler(error)` would have the system terminate the NE
    // before the app gets a chance to read it.
    private var coreError: String?

    override func startTunnel(options _: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let providerConfig = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let coreTypeRaw = (providerConfig["coreType"] as? String) ?? CoreType.xray.rawValue
        let coreType = CoreType(rawValue: coreTypeRaw) ?? .xray
        let dnsServers = Self.cleanDNS(providerConfig["dnsServers"] as? [String])

        // Resolve the user's active config from the shared Core Data
        // store. iOS caps providerConfiguration at 512 KB, so the host
        // app passes only the UUID and we fetch the row ourselves.
        let configContent: String
        do {
            guard let idString = providerConfig["configID"] as? String,
                  let id = UUID(uuidString: idString) else {
                throw NSError(domain: "Everywhere", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "missing configID in providerConfiguration"
                ])
            }
            let raw = try Self.fetchConfigContent(id: id)
            configContent = try ConfigNormalizer.normalize(raw, for: coreType)
        } catch {
            completionHandler(error)
            return
        }

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
            let resPath = EVCore.resourcesURL(for: coreType).path
            var resErr: NSError?
            if !EvcoreSetResourcesPath(resPath, &resErr), let resErr {
                NSLog("Everywhere: SetResourcesPath failed: \(resErr)")
            }

            var coreErr: NSError?
            guard EvcoreStartCore(coreType.rawValue, configContent, Int(fd), Self.tunnelMTU, &coreErr) else {
                self.coreError = coreErr?.localizedDescription ?? "core failed to start"
                completionHandler(nil)
                return
            }

            completionHandler(nil)
        }
    }

    override func stopTunnel(with _: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        // EvcoreStopAll is a synchronous Go call; on rare occasions it
        // hasn't returned (e.g. a stuck core goroutine), which leaves
        // iOS pinned at Disconnecting forever. Run it on a background
        // queue and guarantee completionHandler fires within a few
        // seconds either way — iOS will reap the process if needed.
        let lock = NSLock()
        var didComplete = false
        let complete = {
            lock.lock(); defer { lock.unlock() }
            guard !didComplete else { return }
            didComplete = true
            completionHandler()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSError?
            if !EvcoreStopAll(&err), let err {
                NSLog("Everywhere: StopAll failed: \(err)")
            }
            complete()
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            complete()
        }
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

    private static func fetchConfigContent(id: UUID) throws -> String {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<Configuration>(entityName: "Configuration")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let row = try context.fetch(request).first else {
            throw NSError(domain: "Everywhere", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "active configuration not found in store"
            ])
        }
        return row.content
    }
}
