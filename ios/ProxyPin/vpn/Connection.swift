//
//  Connection.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/17.
//

import Foundation


import Foundation
import Network
import os.log

class Connection{
    var nwProtocol: NWProtocol
    var sourceIp: UInt32
    var sourcePort: UInt16
    var destinationIp: UInt32
    var destinationPort: UInt16
    var channel: NWConnection?
    
    var isInitConnect: Bool = false
    var isConnected: Bool = false
    var isClosingConnection: Bool = false
    var isAbortingConnection: Bool = false
    var isAckedToFin: Bool = false

    private let connectionCloser: ConnectionManager

    init(nwProtocol: NWProtocol, sourceIp: UInt32, sourcePort: UInt16, destinationIp: UInt32, destinationPort: UInt16, connectionCloser: ConnectionManager) {
        self.nwProtocol = nwProtocol
        self.sourceIp = sourceIp
        self.sourcePort = sourcePort
        self.destinationIp = destinationIp
        self.destinationPort = destinationPort
        self.connectionCloser = connectionCloser
    }
    
    //发送缓冲区，用于存储要从vpn客户端发送到目标主机的数据
    var sendBuffer = Data()

    var hasReceivedLastSegment = false
    
    //从客户端接收的最后一个数据包
    var lastIpHeader: IP4Header?
    var lastTcpHeader: TCPHeader?
    var lastUdpHeader: UDPHeader?
    
    var timestampSender = 0
    var timestampReplyTo = 0
    
    //从客户端接收的序列
    var recSequence: UInt32 = 0
    
    //在tcp选项内的SYN期间由客户端发送
    var maxSegmentSize = 0
    
    //跟踪我们发送给客户端的ack，并等待客户端返回ack
    var sendUnAck: UInt32 = 0
    
    //发送到客户端的下一个ack
    var sendNext: UInt32 = 0
    
    static func getConnectionKey(nwProtocol: NWProtocol, destIp: UInt32, destPort: UInt16, sourceIp: UInt32, sourcePort: UInt16) -> String {
        let destIpString = PacketUtil.intToIPAddress(destIp)
        let sourceIpString = PacketUtil.intToIPAddress(sourceIp)
        return "\(nwProtocol)|\(sourceIpString):\(sourcePort)->\(destIpString):\(destPort)"
    }

    func closeConnection() {
        connectionCloser.closeConnection(connection: self)
    }
    
    func addSendData(data: Data) {
       self.sendBuffer.append(data)

        if (self.channel?.state != .ready) {
           os_log("Connection %{public}@ is not ready, cannot send data", log: OSLog.default, type: .debug, self.description)
           return
       }

        self.sendToDestination()
    }
    
    //发送到目标服务器的数据
    func sendToDestination() {
//         os_log("Sending data to destination key %{public}@", log: OSLog.default, type: .debug, self.description)
        if (self.sendBuffer.count == 0) {
            return
        }

        let data = self.sendBuffer
        self.sendBuffer.removeAll()

        self.channel?.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                os_log("Failed to send data to destination key %{public}@ error: %{public}@", log: OSLog.default, type: .error, self.description, error.localizedDescription)
                self.closeConnection()
            }
        }))
    }

    var description: String {
        return Connection.getConnectionKey(nwProtocol: nwProtocol, destIp: destinationIp, destPort: destinationPort, sourceIp: sourceIp, sourcePort: sourcePort)
    }
}
