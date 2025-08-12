//
//  ConnectionHandler.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/16.
//

import Foundation
import NetworkExtension
import Network
import os.log


enum ProtocolType: UInt8 {
      case icmp = 1, tcp = 6, udp = 17
}

/// Handles incoming packets and routes them to the appropriate connection.
class ConnectionHandler {
    private let manager: ConnectionManager
    private let writer: NEPacketTunnelFlow
    private let ioService: SocketIOService
    
    init(manager: ConnectionManager, writer: NEPacketTunnelFlow, ioService: SocketIOService) {
        self.manager = manager
        self.writer = writer
        self.ioService = ioService
    }
    
    //Handle unknown raw IP packet data
    public func handlePacket(packet: Data, version: NSNumber?) {
        guard let ipHeader = IPPacketFactory.createIP4Header(data: packet) else {
            os_log("Malformed IP packet", log: OSLog.default, type: .error)
            return
        }

        if ipHeader.ipVersion != 4 {
            os_log("Unsupported IP version: %d", log: OSLog.default, type: .error, ipHeader.ipVersion)
            return
        }

//         os_log("Handling packet length:%d, protocolNumber: %d", log: OSLog.default, type: .default, packet.count, ipHeader.protocolNumber)

        var clientPacketData = packet.subdata(in: IPPacketFactory.IP4_HEADER_SIZE..<packet.count)

        switch ipHeader.protocolNumber {
            case ProtocolType.tcp.rawValue:
                handleTCPPacket(packet: clientPacketData, ipHeader: ipHeader)
                break
            case ProtocolType.udp.rawValue:
                handleUDPPacket(clientPacketData: clientPacketData, ipHeader: ipHeader)
                break
            case ProtocolType.icmp.rawValue:
                handleICMPPacket(clientPacketData: &clientPacketData, ipHeader: ipHeader)
                break
            default:
                os_log("Unsupported IP protocol: %d", log: OSLog.default, type: .error, ipHeader.protocolNumber)
        }
    }

    func synchronized(_ lock: AnyObject, closure: () -> Void) {
//        objc_sync_enter(lock)
        closure()
//        objc_sync_exit(lock)
    }
    
    private func handleUDPPacket(clientPacketData: Data, ipHeader: IP4Header) {
        guard let udpHeader = UDPPacketFactory.createUDPHeader(from: clientPacketData) else {
            os_log("Malformed UDP packet", log: OSLog.default, type: .error)
            return
        }
        
        var connection = manager.getConnection(
            nwProtocol: .UDP,
            ip: ipHeader.destinationIP,
            port: udpHeader.destinationPort,
            srcIp: ipHeader.sourceIP,
            srcPort: udpHeader.sourcePort
        )
        
        let newSession = connection == nil
        if connection == nil {
            connection = manager.createUDPConnection(
                ip: ipHeader.destinationIP,
                port: udpHeader.destinationPort,
                srcIp: ipHeader.sourceIP,
                srcPort: udpHeader.sourcePort
            )
        }
        
        
        guard let connection = connection else {
            os_log("Failed to create UDP connection", log: OSLog.default, type: .error)
            return
        }

        synchronized(connection) {
            os_log("handle UDP Packet %{public}@", log: OSLog.default, type: .default, connection.description)
            if newSession {
                ioService.registerSession(connection: connection)
            }

            let payload = clientPacketData.subdata(in: UDPPacketFactory.UDP_HEADER_LENGTH..<clientPacketData.count)

            if ((payload.count + UDPPacketFactory.UDP_HEADER_LENGTH) != udpHeader.length) {
                os_log("UDP  %{public}@  packet length mismatch: expected %d, got %d", log: OSLog.default, type: .error, connection.description, udpHeader.length, payload.count)
            }
//             os_log("Received UDP packet", log: OSLog.default, type: .default)
            connection.lastIpHeader = ipHeader
            connection.lastUdpHeader = udpHeader
            manager.addClientData(data: payload, connection: connection)
        }
        manager.keepSessionAlive(connection: connection)
    }
    
    func printByteArray(_ byteArray: Data) {
        let byteArrayString = byteArray.map { String( format: "0x%02X",$0) }.joined(separator: ",")
        os_log("Packet data: %{public}@", log: OSLog.default, type: .default, byteArrayString)
    }
    
    private func handleTCPPacket(packet: Data, ipHeader: IP4Header) {
        guard let tcpHeader = TCPPacketFactory.createTCPHeader(data: packet) else {
            os_log("Malformed TCP packet", log: OSLog.default, type: .error)
            return
        }
        
        let dataLength = tcpHeader.payload?.count ?? 0
        let sourceIP = ipHeader.sourceIP
        let destinationIP = ipHeader.destinationIP
        let sourcePort = tcpHeader.sourcePort
        let destinationPort = tcpHeader.destinationPort

        let key = Connection.getConnectionKey(nwProtocol: .TCP, destIp: destinationIP, destPort: destinationPort, sourceIp: sourceIP, sourcePort: sourcePort)
        
        if (tcpHeader.isSYN()) {
            os_log("Received SYN packet %{public}@ seq:%u", log: OSLog.default, type: .default, key, tcpHeader.sequenceNumber)
            // 3-way handshake + create new session
            replySynAck(ipHeader: ipHeader, tcpHeader: tcpHeader)
        } else if (tcpHeader.isACK()) {
//            os_log("Received ACK packet for key: %{public}@", log: OSLog.default, type: .debug, key)

            guard let connection = manager.getConnectionByKey(key: key) else {
                os_log("Ack for unknown session: %{public}@", log: OSLog.default, type: .default, key)
                if tcpHeader.isFIN() {
                    sendLastAck(ip: ipHeader, tcp: tcpHeader)
               } else if !tcpHeader.isRST() {
                   sendRstPacket(ip: ipHeader, tcp: tcpHeader, dataLength: dataLength)
                }
                return
            }

            synchronized(connection) {
                connection.lastIpHeader = ipHeader
                connection.lastTcpHeader = tcpHeader

                if dataLength > 0 {
//                     os_log("[ConnectionHandler] Received data packet %{public}@ length:%d seq:%u, ack:%u", log: OSLog.default, type: .default, connection.description, dataLength, tcpHeader.sequenceNumber, tcpHeader.ackNumber)
                    
                    //init proxy
                    self.initProxyConnect(packetData: tcpHeader.payload!, destinationIP: destinationIP, destinationPort: destinationPort, connection: connection)
                  
                    manager.addClientData(data: tcpHeader.payload!, connection: connection)
                    sendAck(ipHeader: ipHeader, tcpHeader: tcpHeader, acceptedDataLength: dataLength, connection: connection)
                } else {
//                      os_log("[ConnectionHandler] Received ACK packet %{public}@ seq:%u, ack:%u", log: OSLog.default, type: .default, connection.description, tcpHeader.sequenceNumber, tcpHeader.ackNumber)
                }

                acceptAck(tcpHeader: tcpHeader, connection: connection)
                
                if connection.isClosingConnection {
                    sendFinAck(ipHeader: ipHeader, tcpHeader: tcpHeader, connection: connection)
                } else if connection.isAckedToFin && !tcpHeader.isFIN() {
                    manager.closeConnection(nwProtocol: .TCP, ip: destinationIP, port: destinationPort, srcIp: sourceIP, srcPort: sourcePort)
                }

                //received the last segment of data from vpn client
                if tcpHeader.isPSH() {
                    // Tell the NIO thread to immediately send data to the destination
                    pushDataToDestination(connection: connection, tcpHeader: tcpHeader)
                } else if tcpHeader.isFIN() {
                    //fin from vpn client is the last packet
                    //ack it
                    ackFinAck(ipHeader: ipHeader, tcpHeader: tcpHeader, connection: connection)
                } else if tcpHeader.isRST() {
                    resetTCPConnection(ip: ipHeader, tcp: tcpHeader)
                }

                if !connection.isAbortingConnection {
                    manager.keepSessionAlive(connection: connection)
                }
            }
        } else if tcpHeader.isFIN() {
            os_log("Received FIN packet %{public}@:%d seq:%u", log: OSLog.default, type: .default, PacketUtil.intToIPAddress(destinationIP), destinationPort, tcpHeader.sequenceNumber)
            //case client sent FIN without ACK
            guard let connection = manager.getConnection(nwProtocol: .TCP, ip: destinationIP, port: destinationPort, srcIp: sourceIP, srcPort: sourcePort) else {
                ackFinAck(ipHeader: ipHeader, tcpHeader: tcpHeader, connection: nil)
                return
            }
            
            manager.keepSessionAlive(connection: connection)
        } else if tcpHeader.isRST() {
            os_log("Received RST packet %{public}@:%d seq:%u", log: OSLog.default, type: .debug, PacketUtil.intToIPAddress(destinationIP), destinationPort, tcpHeader.sequenceNumber)
            resetTCPConnection(ip: ipHeader, tcp: tcpHeader)
        } else {
            os_log("Unknown TCP flag", log: OSLog.default, type: .error)
        }
    }

    private func initProxyConnect(
        packetData: Data,
        destinationIP: UInt32,
        destinationPort: UInt16,
        connection: Connection
    ) {
        guard !connection.isInitConnect else {
            return
        }

        connection.isInitConnect = true

        let supportsProtocol = supportsProtocol(packetData: packetData)
        
        let endpoint: Network.NWEndpoint
        if (supportsProtocol && manager.proxyAddress != nil) {
            endpoint = manager.proxyAddress!
        } else {
            let ipString = PacketUtil.intToIPAddress(destinationIP)
            endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ipString), port: NWEndpoint.Port(rawValue: destinationPort)!)
        }
        
        // 使用 TCP 协议
        let parameters = NWParameters.tcp
        let nwConnection = NWConnection(to: endpoint, using: parameters)
        connection.channel = nwConnection
        connection.isInitConnect = true
        self.ioService.registerSession(connection: connection)
    }

    private let methods: [String] = [
        "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT", "PROPFIND", "REPORT"
    ]

    private func supportsProtocol(packetData: Data) -> Bool {
        let position = packetData.startIndex
        // 判断是否是 SSL 握手
        if TLS.isTLSClientHello(packetData: packetData) {
            return true
        }

        // 检查是否包含 HTTP 方法
        for method in methods {
            if packetData.count - position < method.count {
                continue
            }
            let range = position..<(position + method.count)
            if let substring = String(data: packetData.subdata(in: range), encoding: .utf8),
               method.caseInsensitiveCompare(substring) == .orderedSame {
                return true
            }
        }
        return false
    }

    //set connection as aborting so that background worker will close it.
    func resetTCPConnection(ip: IP4Header, tcp: TCPHeader) {
        let session = manager.getConnection(nwProtocol: .TCP, ip: ip.destinationIP, port: tcp.destinationPort, srcIp: ip.sourceIP, srcPort: tcp.sourcePort)
        if let session = session {
            session.isAbortingConnection = true
        }
    }

    func ackFinAck(ipHeader: IP4Header, tcpHeader: TCPHeader, connection: Connection?) {
        let ackNumber = tcpHeader.sequenceNumber + 1
        let seqNumber = tcpHeader.ackNumber
        let finAckData = TCPPacketFactory.createFinAckData(ipHeader: ipHeader, tcpHeader: tcpHeader, ackToClient: ackNumber, seqToClient: seqNumber, isFin: true, isAck: true)
        write(data: finAckData)
//        os_log("Sent FIN-ACK packet ack# %{public}d, seq# %{public}d", log: OSLog.default, type: .default, ackNumber, seqNumber)
        if let connection = connection {
            manager.closeConnection(connection: connection)
        }
    }

    func pushDataToDestination(connection: Connection, tcpHeader: TCPHeader) {
        connection.timestampReplyTo = tcpHeader.timeStampSender
        connection.timestampSender = Int(Date().timeIntervalSince1970)
    }
    
    func sendFinAck(ipHeader: IP4Header, tcpHeader: TCPHeader, connection: Connection) {
        let ackNumber = tcpHeader.sequenceNumber
        let seqNumber = tcpHeader.ackNumber
        let finAckData = TCPPacketFactory.createFinAckData(ipHeader: ipHeader, tcpHeader: tcpHeader, ackToClient: ackNumber, seqToClient: seqNumber, isFin: true, isAck: false)
        write(data: finAckData)

        connection.sendNext = seqNumber + 1
        connection.isClosingConnection = false
    }
    
    //acknowledge a packet.
    func acceptAck(tcpHeader: TCPHeader, connection: Connection) {
        let isCorrupted = PacketUtil.isPacketCorrupted(tcpHeader: tcpHeader)

        if isCorrupted {
            os_log("Packet is corrupted", log: OSLog.default, type: .error)
        }

        if (tcpHeader.sequenceNumber > connection.recSequence) {
            connection.recSequence = tcpHeader.sequenceNumber
       }

        if tcpHeader.ackNumber >= connection.sendUnAck - 1 || tcpHeader.ackNumber == connection.sendNext {
            connection.sendUnAck = tcpHeader.ackNumber

            connection.timestampReplyTo = tcpHeader.timeStampSender
            connection.timestampSender = Int(Date().timeIntervalSince1970)
        } else {
            os_log("%{public}@ Not accepting ack# %d, it should be: %d", log: OSLog.default, type: .error, connection.description ,tcpHeader.ackNumber, connection.sendNext)
            os_log("%{public}@ Previous sendUnAck: %d", log: OSLog.default, type: .error, connection.description, connection.sendUnAck)
        }
    }
    
    func sendAckForDisorder(ipHeader: IP4Header, tcpHeader: TCPHeader, acceptedDataLength: Int) {
        let ackNumber = tcpHeader.sequenceNumber + UInt32(acceptedDataLength)
//        os_log("Sent disorder ack, ack# %{public}d", log: OSLog.default, type: .debug, ackNumber)
        let ackData = TCPPacketFactory.createResponseAckData(ipHeader: ipHeader, tcpHeader: tcpHeader, ackToClient: ackNumber)
        write(data: ackData)
    }
    
    func sendAck(ipHeader: IP4Header, tcpHeader: TCPHeader, acceptedDataLength: Int, connection: Connection) {
       synchronized(connection) {
            let ackNumber = (tcpHeader.sequenceNumber + UInt32(acceptedDataLength)) % UInt32.max
            connection.recSequence = ackNumber
            let ackData = TCPPacketFactory.createResponseAckData(ipHeader: ipHeader, tcpHeader: tcpHeader, ackToClient: ackNumber)
            self.write(data: ackData)

//             os_log("[ConnectionHandler] Sent ACK packet to client %{public}@ ack: %u", log: OSLog.default, type: .default, connection.description, ackNumber)
        }
    }

    private func sendLastAck(ip: IP4Header, tcp: TCPHeader) {
        let data = TCPPacketFactory.createResponseAckData(ipHeader: ip, tcpHeader: tcp, ackToClient: tcp.sequenceNumber + 1)
        self.write(data: data)
        os_log("Sent last ACK Packet to client with dest => %{public}@:%{public}d", log: OSLog.default, type: .debug, PacketUtil.intToIPAddress(ip.destinationIP), tcp.destinationPort)
    }

    private func sendRstPacket(ip: IP4Header, tcp: TCPHeader, dataLength: Int) {
        let data = TCPPacketFactory.createRstData(ipHeader: ip, tcpHeader: tcp, dataLength: dataLength)
        self.write(data: data)
        os_log("Sent RST Packet to client with dest => %{public}@:%{public}d", log: OSLog.default, type: .debug, PacketUtil.intToIPAddress(ip.destinationIP), tcp.destinationPort)
    }
    
    //create a new client's session and SYN-ACK packet data to respond to client
    private func replySynAck(ipHeader: IP4Header, tcpHeader: TCPHeader) -> Void {
        ipHeader.identification = 0
        let packet = TCPPacketFactory.createSynAckPacketData(ipHeader: ipHeader, tcpHeader: tcpHeader)

        guard let tcpTransport = packet.transportHeader as? TCPHeader else {
            os_log("Failed to extract TCP header from packet", log: OSLog.default, type: .error)
            return
        }
        
        let connection = manager.createTCPConnection(
            ip: ipHeader.destinationIP,
            port: tcpHeader.destinationPort,
            srcIp: ipHeader.sourceIP,
            srcPort: tcpHeader.sourcePort
        )
        
        if connection.lastIpHeader != nil {
            resendAck(connection: connection)
            return
        }
        
        synchronized(connection) {
            connection.maxSegmentSize = Int(tcpTransport.maxSegmentSize)
            connection.sendUnAck = tcpTransport.sequenceNumber
            connection.sendNext = tcpTransport.sequenceNumber + 1
            
            //client initial sequence has been incremented by 1 and set to ack
            connection.recSequence = tcpTransport.ackNumber
            connection.lastIpHeader = ipHeader
            connection.lastTcpHeader = tcpHeader
            if connection.isInitConnect {
                self.ioService.registerSession(connection: connection)
            }
            self.write(data: packet.buffer)
//             os_log("SYN-ACK %{public}@ packet length:%d sent ack:%u", log: OSLog.default, type: .default, connection.description, packet.buffer.count, tcpTransport.ackNumber)
        }
    }

    /**
     * resend the last acknowledgment packet to VPN client, e.g. when an unexpected out of order
     * packet arrives.
     */
    private func resendAck(connection: Connection) {
        let data = TCPPacketFactory.createResponseAckData(
            ipHeader: connection.lastIpHeader!,
            tcpHeader: connection.lastTcpHeader!,
            ackToClient: connection.recSequence
        )
//         os_log("Resending ACK packet %{public}@ ackToClient: %d", log: OSLog.default, type: .default, connection.description, connection.recSequence)
        self.write(data: data)
    }


    private func write(data: Data) {
        self.writer.writePackets([data], withProtocols: [NSNumber(value: AF_INET)])
    }

    private func handleICMPPacket(clientPacketData: inout Data, ipHeader: IP4Header) {
        guard let requestPacket = ICMPPacketFactory.parseICMPPacket(&clientPacketData) else {
            os_log("Failed to parse ICMP packet", log: OSLog.default, type: .error)
            return
        }

//         os_log("Handling ICMP packet type: %d", log: OSLog.default, type: .default, requestPacket.type)
        if requestPacket.type == ICMPPacket.DESTINATION_UNREACHABLE_TYPE {
             // This is a packet from the phone, telling somebody that a destination is unreachable.
             // Might be caused by issues on our end, but it's unclear what kind of issues. Regardless,
             // we can't send ICMP messages ourselves or react usefully, so we drop these silently.

            return
        } else if requestPacket.type != ICMPPacket.ECHO_REQUEST_TYPE {
            // We only actually support outgoing ping packets. Loudly drop anything else:
            os_log("Unknown ICMP type: %d", log: OSLog.default, type: .error, requestPacket.type)
            return
        }

          QueueFactory.instance.getQueue().async {
              
            if !self.isReachable(ipAddress: PacketUtil.intToIPAddress(ipHeader.destinationIP)) {
                os_log("Failed ping, ignoring", log: OSLog.default, type: .default)
                return
            }

            let response = ICMPPacketFactory.buildSuccessPacket(requestPacket)

            // Flip the address
            let destination = ipHeader.destinationIP
            let source = ipHeader.sourceIP
            ipHeader.sourceIP = destination
            ipHeader.destinationIP = source

            let responseData = ICMPPacketFactory.packetToBuffer(ipHeader: ipHeader, packet: response)
            os_log("Successful ping response", log: OSLog.default, type: .default)
            self.write(data: responseData)
        }
    }

    private func isReachable(ipAddress: String) -> Bool {
        do {
            return true
//            return try InetAddress.getByName(ipAddress).isReachable(timeout: 10000)
        } catch {
            return false
        }
    }
}
