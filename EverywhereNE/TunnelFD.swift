//
//  TunnelFD.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Darwin
import NetworkExtension

enum TunnelFD {
    private static let afSystem: UInt8 = 32
    private static let sysprotoControl: Int32 = 2
    private static let utunOptIfname: Int32 = 2

    static func lookup(for _: NEPacketTunnelFlow) -> Int32 {
        for fd in Int32(0)..<1024 {
            if isUtunSocket(fd) { return fd }
        }
        return -1
    }

    private static func isUtunSocket(_ fd: Int32) -> Bool {
        var saBuf = [UInt8](repeating: 0, count: 32)
        var saLen = socklen_t(saBuf.count)
        let getRes = saBuf.withUnsafeMutableBufferPointer { buf -> Int32 in
            buf.baseAddress!.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getpeername(fd, sa, &saLen)
            }
        }
        guard getRes == 0, saBuf[1] == afSystem else { return false }

        var nameBuf = [CChar](repeating: 0, count: 96)
        var nameLen = socklen_t(nameBuf.count)
        let optRes = nameBuf.withUnsafeMutableBufferPointer { buf in
            getsockopt(fd, sysprotoControl, utunOptIfname, buf.baseAddress, &nameLen)
        }
        return optRes == 0
    }
}
