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
import os

final class PacketTunnelProvider: NEPacketTunnelProvider {
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
        let networkSettings = EVCore.getTunnelNetworkSettings()
        
        let configID: UUID
        let configContent: String
        do {
            guard let idString = providerConfig["configID"] as? String,
                  let id = UUID(uuidString: idString) else {
                throw NSError(domain: "Everywhere", code: -2, userInfo: [
                    NSLocalizedDescriptionKey: "missing configID in providerConfiguration"
                ])
            }
            configID = id
            let raw = try Self.fetchConfigContent(id: id)
            configContent = try ConfigNormalizer.normalize(
                raw,
                for: coreType,
                tunnel: networkSettings,
                dashboard: EVCore.getDashboardEnabled()
                    ? DashboardAccess(secret: EVCore.makeControllerSecret())
                    : nil
            )
        } catch {
            completionHandler(error)
            return
        }

        setTunnelNetworkSettings(networkSettings.makePacketTunnelSettings()) { [weak self] error in
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
            guard EvcoreStartCore(coreType.rawValue, configContent, Int(fd), networkSettings.mtu, &coreErr) else {
                self.coreError = coreErr?.localizedDescription ?? "core failed to start"
                completionHandler(nil)
                return
            }
            if coreType == .xray {
                Self.replayXraySelections(configID: configID)
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
        case "runtime":
            var response: [String: Any] = [
                "available": UInt64(os_proc_available_memory()),
            ]
            if let footprint = Self.memoryFootprint() { response["footprint"] = footprint }
            completionHandler?(try? JSONSerialization.data(withJSONObject: response))
        case "control":
            let method = json["method"] as? String ?? ""
            let params = json["params"] as? String ?? ""
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSError?
                let result = EvcoreControl(method, params, &error)
                let response: [String: Any] = error.map {
                    ["ok": false, "error": $0.localizedDescription]
                } ?? ["ok": true, "result": result]
                completionHandler?(try? JSONSerialization.data(withJSONObject: response))
            }
        default:
            completionHandler?(nil)
        }
    }

    private static func replayXraySelections(configID: UUID) {
        for (balancer, target) in EVCore.getXraySelections(configID: configID) {
            guard let params = try? JSONSerialization.data(
                withJSONObject: ["balancer": balancer, "target": target]
            ) else { continue }
            var error: NSError?
            _ = EvcoreControl("select", String(decoding: params, as: UTF8.self), &error)
            if let error {
                NSLog("Everywhere: could not restore \(balancer) → \(target): \(error.localizedDescription)")
            }
        }
    }

    private static func memoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
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
