//
//  ProxySocketIOService.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/17.
//

import Foundation
import NetworkExtension
import os.log

class SocketIOService {
//    private static let maxReceiveBufferSize = 16384
    private static let maxReceiveBufferSize = 1480

    private let queue: DispatchQueue = DispatchQueue(label: "ProxyPin.SocketIOService", attributes: .concurrent)

    private var clientPacketWriter: NEPacketTunnelFlow

    private var shutdown = false

    init(clientPacketWriter: NEPacketTunnelFlow) {
        self.clientPacketWriter = clientPacketWriter
    }

    public func stop() {
        os_log("Stopping SocketIOService", log: OSLog.default, type: .default)
        queue.async(flags: .barrier) {
            self.shutdown = true
        }
//        queue.suspend()
    }

    //从connection接受数据 写到client
    public func registerSession(connection: Connection) {
        
        connection.channel!.stateUpdateHandler = { state in
//             os_log("Connection %{public}@ state changed to %{public}@", log: OSLog.default, type: .default, connection.description, String(describing: state))
            switch state {

            case .ready:
                connection.isConnected = true
                os_log("Connected to %{public}@ on receiveMessage", log: OSLog.default, type: .default, connection.description)

                //接受远程服务器的数据
                connection.sendToDestination()
                self.receiveMessage(connection: connection)
            case .cancelled:
                connection.isConnected = false
                os_log("Connection cancelled  %{public}@", log: OSLog.default, type: .default, connection.description)
                connection.closeConnection()
                self.sendFin(connection: connection)

            case .failed(let error):
                connection.isConnected = false
                os_log("Failed to connect: %{public}@ %{public}@", log: OSLog.default, type: .error,connection.description, error.localizedDescription)
                connection.closeConnection()
            default:
                os_log("Connection %{public}@ entered unhandled state: %{public}@", log: OSLog.default, type: .default, connection.description, String(describing: state))
                break
            }
        }

        connection.channel!.start(queue: self.queue)
    }

    private func receiveMessage(connection: Connection) {
        if (shutdown) {
            os_log("SocketIOService is shutting down", log: OSLog.default, type: .default)
            return
        }

        if (connection.nwProtocol == .UDP) {
            readUDP(connection: connection)
        } else {
            readTCP(connection: connection)
        }

        if (connection.isAbortingConnection) {
            os_log("Connection is aborting", log: OSLog.default, type: .default)
            connection.closeConnection()
            return
        }
    }

    func readTCP(connection: Connection) {
//         os_log("Reading from TCP socket")
        if connection.isAbortingConnection {
            os_log("Connection is aborting", log: OSLog.default, type: .default)
            return
        }

        guard let channel = connection.channel else {
            os_log("Invalid channel type", log: OSLog.default, type: .error)
            return
        }
        
        channel.receive(minimumIncompleteLength: 1, maximumLength: Self.maxReceiveBufferSize) { (data, context, isComplete, error) in
            self.queue.async(flags: .barrier) {
//                 os_log("[SocketIOService] Received TCP data packet %{public}@ length %d", log: OSLog.default, type: .default, connection.description, data?.count ?? -1)
                if let error = error {
                    os_log("Failed to read from TCP socket: %@", log: OSLog.default, type: .error, error as CVarArg)
                    connection.isAbortingConnection = true
                    return
                }

                self.pushDataToClient(buffer: data ?? Data() , connection: connection)

                // Recursively call readTCP to continue reading messages
                self.receiveMessage(connection: connection)
                
                if (isComplete) {
                    connection.isAbortingConnection = true
                    return
                }
            }
        }
    }
    
    func synchronized(_ lock: AnyObject, closure: () -> Void) {
//        objc_sync_enter(lock)
        closure()
//        objc_sync_exit(lock)
    }
    
    ///create packet data and send it to VPN client
    private func pushDataToClient(buffer: Data, connection: Connection) {
        // Last piece of data is usually smaller than MAX_RECEIVE_BUFFER_SIZE. We use this as a
        // trigger to set PSH on the resulting TCP packet that goes to the VPN.

        connection.hasReceivedLastSegment = buffer.count <= 0

        guard let ipHeader = connection.lastIpHeader, let tcpHeader = connection.lastTcpHeader else {
            os_log("Invalid ipHeader or tcpHeader", log: OSLog.default, type: .error)
            return
        }

        synchronized(connection) {
            let unAck = connection.sendNext
            //处理益处问题
            let nextUnAck = UInt32(truncatingIfNeeded: (connection.sendNext + UInt32(buffer.count)) % UInt32.max)
            connection.sendNext = nextUnAck

            let data = TCPPacketFactory.createResponsePacketData(
                ipHeader: ipHeader,
                tcpHeader: tcpHeader,
                packetData: buffer,
                isPsh: connection.hasReceivedLastSegment,
                ackNumber: connection.recSequence,
                seqNumber: unAck,
                timeSender: connection.timestampSender,
                timeReplyTo: connection.timestampReplyTo
            )

            self.clientPacketWriter.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
//              os_log("[SocketIOService] Sent TCP data packet to client %{public}@ length:%d  seq:%u ack:%u", log: OSLog.default, type: .default, connection.description, buffer.count, unAck, connection.recSequence)
        }
    }

    private func sendFin(connection: Connection) {
        if (connection.nwProtocol != .TCP) {
            return
        }
        
        guard let ipHeader = connection.lastIpHeader, let tcpHeader = connection.lastTcpHeader else {
            os_log("Invalid ipHeader or tcpHeader", log: OSLog.default, type: .error)
            return
        }
        synchronized(connection) {
            let data = TCPPacketFactory.createFinData(
                ipHeader: ipHeader,
                tcpHeader: tcpHeader,
                ackNumber: connection.recSequence,
                seqNumber: connection.sendNext,
                timeSender: connection.timestampSender,
                timeReplyTo: connection.timestampReplyTo
            )
            
            self.clientPacketWriter.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
        }
    }
    
    func readUDP(connection: Connection) {
 
        guard let channel = connection.channel else {
            os_log("Invalid channel type", log: OSLog.default, type: .error)
            return
        }

        channel.receive(minimumIncompleteLength: 1, maximumLength: 65507) { (data, context, isComplete, error) in
                self.queue.async(flags: .barrier) {
                if let error = error {
                    os_log("Failed to read from UDP socket: %@", log: OSLog.default, type: .error, error as CVarArg)
                    connection.isAbortingConnection = true
                    return
                }

//                os_log("Received UDP data packet length %d", log: OSLog.default, type: .debug, data?.count ?? 0)

                guard let data = data, !data.isEmpty else {
                    return
                }
                
                guard let ipHeader = connection.lastIpHeader, let udpHeader = connection.lastUdpHeader else {
                    os_log("Missing IP or UDP header for connection %{public}@", log: OSLog.default, type: .error, connection.description)
                    return
                }
                
                let packetData = UDPPacketFactory.createResponsePacket(
                    ip: ipHeader,
                    udp: udpHeader,
                    packetData: data
                )

                self.clientPacketWriter.writePackets([packetData], withProtocols: [NSNumber(value: AF_INET)])

                // Recursively call receiveMessage to continue receiving messages
                self.receiveMessage(connection: connection)
            }
        }
    }
}
