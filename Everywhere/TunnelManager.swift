//
//  TunnelManager.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import Combine
import Foundation
import NetworkExtension

final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var isReady: Bool = false
    @Published private(set) var coreRunning: Bool = false
    @Published private(set) var lastError: String?
    private var manager: NETunnelProviderManager?
    private var statusObserver: AnyCancellable?

    private init() {
        setupStatusObserver()
        Task { await reload() }
    }

    func reload() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppGroup.extensionBundleID
            }) ?? managers.first ?? NETunnelProviderManager()
            self.manager = m
            self.status = m.connection.status
            self.isReady = true
            if m.connection.status == .connected {
                queryCoreStatus()
            }
        } catch {
            self.lastError = error.localizedDescription
            self.isReady = true
        }
    }

    func setEnabled(_ on: Bool, configuration: Configuration?) async {
        guard let configuration else {
            lastError = "No configuration is active."
            return
        }
        do {
            let normalized = try ConfigNormalizer.normalize(configuration.content, for: configuration.coreType)
            let m = try await ensureManager(coreType: configuration.coreType, configContent: normalized)
            if on {
                try m.connection.startVPNTunnel()
            } else {
                m.connection.stopVPNTunnel()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearLastError() {
        lastError = nil
    }

    private func ensureManager(coreType: CoreType, configContent: String) async throws -> NETunnelProviderManager {
        let m = manager ?? NETunnelProviderManager()
        let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = AppGroup.extensionBundleID
        proto.serverAddress = "Everywhere"
        proto.providerConfiguration = [
            "coreType": coreType.rawValue,
            "configContent": configContent,
            "dnsServers": AppState.shared.dnsServers
        ]
        m.protocolConfiguration = proto
        m.localizedDescription = AppGroup.tunnelDescription
        m.isEnabled = true
        try await m.saveToPreferences()
        try await m.loadFromPreferences()
        manager = m
        return m
    }

    private func setupStatusObserver() {
        statusObserver = NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .compactMap { $0.object as? NEVPNConnection }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connection in
                guard let self else { return }
                guard connection === self.manager?.connection else { return }
                self.status = connection.status
                if connection.status == .connected {
                    self.queryCoreStatus()
                } else {
                    self.coreRunning = false
                }
            }
    }

    // The NE keeps itself alive on a core start failure so we can fetch the
    // reason here. When the response says the core isn't running, surface
    // the message and tear the tunnel down — the NE has nothing useful to
    // route through, but iOS thinks it's connected.
    private func queryCoreStatus() {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let message: [String: Any] = ["type": "core-status"]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do {
            try session.sendProviderMessage(data) { [weak self] response in
                guard let self,
                      let response,
                      let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
                else { return }
                let running = json["running"] as? Bool ?? true
                let error = json["error"] as? String
                DispatchQueue.main.async {
                    // Status may have changed while the IPC was in flight;
                    // only mark the core as running if we're still connected.
                    guard self.status == .connected else { return }
                    if running {
                        self.coreRunning = true
                    } else {
                        self.coreRunning = false
                        self.lastError = error ?? "Core failed to start."
                        session.stopVPNTunnel()
                    }
                }
            }
        } catch {
            // ignore — NE may have died between the status flip and the send
        }
    }
}

extension NEVPNStatus {
    var isTransitioning: Bool {
        self == .connecting || self == .disconnecting || self == .reasserting
    }

    var isActive: Bool {
        self == .connected || isTransitioning
    }
}
