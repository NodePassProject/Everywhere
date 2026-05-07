//
//  ExampleConfigs.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import Foundation

// Minimal starter configs. Each one routes everything through a
// placeholder direct outbound — replace it with your real proxy server
// before use. The SOCKS inbound on 127.0.0.1:10808 that the
// PacketTunnelProvider hands to tun2socks is injected by
// ConfigNormalizer at start time, so don't add one here (a duplicate
// would make sing-box fail to bind with "address already in use").
//
// mihomo and sing-box also expose the clash-compat REST API on
// 127.0.0.1:9090 — that's the address the bundled yacd dashboard
// (Controller tab) talks to. Xray-core has no clash API.
enum ExampleConfigs {
    static let xray = #"""
    {
      "log": {"loglevel": "warning"},
      "inbounds": [],
      "outbounds": [
        {"tag": "direct", "protocol": "freedom"}
      ]
    }
    """#

    static let singbox = #"""
    {
      "log": {"level": "warn"},
      "inbounds": [],
      "outbounds": [
        {"type": "direct", "tag": "direct"}
      ],
      "experimental": {
        "clash_api": {
          "external_controller": "127.0.0.1:9090"
        }
      }
    }
    """#

    static let mihomo = """
    log-level: warning
    external-controller: 127.0.0.1:9090
    mode: rule
    proxies: []
    proxy-groups: []
    rules:
      - MATCH,DIRECT
    """
}
