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
    enum State: Equatable {
        case loading
        case disconnected
        case connecting
        case connected
        case disconnecting
        case failed(String)
    }

    static let shared = TunnelManager()

    @Published private(set) var state: State = .loading
    private var manager: NETunnelProviderManager?
    private var statusObserver: NSObjectProtocol?

    private init() {
        Task { await reload() }
    }

    deinit {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
    }

    func reload() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = managers.first ?? NETunnelProviderManager()
            self.manager = m
            self.state = Self.translate(m.connection.status)
            installStatusObserver(for: m)
        } catch {
            self.state = .failed(error.localizedDescription)
        }
    }

    func setEnabled(_ on: Bool, configuration: Configuration?) async {
        guard let configuration else {
            state = .failed("No configuration is active.")
            return
        }
        do {
            let normalized = try ConfigNormalizer.normalize(configuration.content, for: configuration.coreType)
            let m = try await ensureManager(coreType: configuration.coreType, configContent: normalized)
            if on {
                state = .connecting
                try m.connection.startVPNTunnel()
            } else {
                state = .disconnecting
                m.connection.stopVPNTunnel()
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
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
        installStatusObserver(for: m)
        return m
    }

    private func installStatusObserver(for m: NETunnelProviderManager) {
        if let statusObserver { NotificationCenter.default.removeObserver(statusObserver) }
        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: m.connection,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.state = Self.translate(m.connection.status)
        }
    }

    private static func translate(_ status: NEVPNStatus) -> State {
        switch status {
        case .invalid, .disconnected: return .disconnected
        case .connecting, .reasserting: return .connecting
        case .connected: return .connected
        case .disconnecting: return .disconnecting
        @unknown default: return .disconnected
        }
    }
}
