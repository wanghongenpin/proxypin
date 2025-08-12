//
//  ProxyService.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/17.
//

import Foundation
import NetworkExtension
import Network
import os.log

class ProxyVpnService {

    private var packetFlow: NEPacketTunnelFlow
    private var connectionHandler: ConnectionHandler
    private var socketIOService: SocketIOService
    private var isRunning = true;
    
    init(packetFlow: NEPacketTunnelFlow, proxyAddress: Network.NWEndpoint?) {
        self.packetFlow = packetFlow
        self.socketIOService = SocketIOService(clientPacketWriter: packetFlow)
        let manager = ConnectionManager()
        manager.proxyAddress = proxyAddress
        self.connectionHandler = ConnectionHandler(manager: manager, writer: packetFlow, ioService: socketIOService)
    }
    
    
    /**
     Start processing packets, this should be called after registering all IP stacks.
     
     A stopped interface should never start again. Create a new interface instead.
     */
    func start() {
        isRunning = true;
        self.readPackets()
    }

    func stop() {
        isRunning = false;
        self.socketIOService.stop()
    }
    
    func readPackets() -> Void {
        if (!isRunning) {
            return
        }

        self.packetFlow.readPackets { (packets, protocols) in
            
//             os_log("Read %d packets", packets.count)
            for (i, packet) in packets.enumerated() {
                 self.connectionHandler.handlePacket(packet: packet, version: protocols[i])
            }
            self.readPackets()
        }
    }
}
