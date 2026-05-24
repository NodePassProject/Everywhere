//
//  PacketTunnelProvider.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import CoreData
import EverywhereCore
import Network
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private static let tunnelMTU = 1500
    
    private var coreError: String?
    
    private var pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "com.argsment.Everywhere.pathMonitor", qos: .utility)
    private var pendingPathUpdate: DispatchWorkItem?
    private var latestPath: Network.NWPath?
    private static let pathDebounceInterval: DispatchTimeInterval = .milliseconds(1000)

    override func startTunnel(options _: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let providerConfig = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let coreTypeRaw = (providerConfig["coreType"] as? String) ?? CoreType.xray.rawValue
        let coreType = CoreType(rawValue: coreTypeRaw) ?? .xray
        let dnsServers = Self.cleanDNS(providerConfig["dnsServers"] as? [String])
        
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

            self.startPathMonitor()

            completionHandler(nil)
        }
    }

    override func stopTunnel(with _: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopPathMonitor()
        
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
    
    override func sleep(completionHandler: @escaping () -> Void) {
        var err: NSError?
        _ = EvcoreSuspend(&err)
        completionHandler()
    }

    override func wake() {
        var err: NSError?
        _ = EvcoreResume(&err)
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

    private func startPathMonitor() {
        stopPathMonitor()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] (path: Network.NWPath) in
            self?.schedulePathUpdate(path)
        }
        monitor.start(queue: pathMonitorQueue)
        pathMonitor = monitor
    }

    private func stopPathMonitor() {
        pendingPathUpdate?.cancel()
        pendingPathUpdate = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }
    
    private func schedulePathUpdate(_ path: Network.NWPath) {
        latestPath = path
        pendingPathUpdate?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let latest = self.latestPath else { return }
            self.handlePathUpdate(latest)
        }
        pendingPathUpdate = work
        pathMonitorQueue.asyncAfter(deadline: .now() + Self.pathDebounceInterval, execute: work)
    }

    private func handlePathUpdate(_ path: Network.NWPath) {
        var err: NSError?
        guard path.status == .satisfied, let iface = path.availableInterfaces.first else {
            // No usable path
            _ = EvcoreUpdateDefaultInterface("", -1, false, false, &err)
            return
        }
        _ = EvcoreUpdateDefaultInterface(
            iface.name,
            Int32(iface.index),
            path.isExpensive,
            path.isConstrained,
            &err
        )
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
