//
//  ClientPacketWriter.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/

import Foundation
import NetworkExtension

class ClientPacketWriter: NSObject {
    private var packetFlow: NEPacketTunnelFlow
    private var isShutdown = false

    init(packetFlow: NEPacketTunnelFlow) {
        self.packetFlow = packetFlow
    }

    func write(data: Data) {
        self.packetFlow.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
    }

    func shutdown() {
        self.isShutdown = true
    }
}

