//
//  ExampleConfigs.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Foundation

nonisolated enum ExampleConfigs {
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
