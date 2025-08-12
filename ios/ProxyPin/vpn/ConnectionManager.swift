//
//  ConnectionManager.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/16.
//

import Foundation
import Network
import os.log

//管理VPN客户端的连接
class ConnectionManager : CloseableConnection{
    //static let instance = ConnectionManager()
    
    private var table: [String: Connection] = [:]

    public var proxyAddress: NWEndpoint?
    
    private let defaultPorts: [UInt16] = [80, 443, 8080, 8088, 8888, 9000]
    
   
    func getConnection(nwProtocol: NWProtocol, ip: UInt32, port: UInt16, srcIp: UInt32, srcPort: UInt16) -> Connection? {
        let key = Connection.getConnectionKey(nwProtocol: nwProtocol, destIp: ip, destPort: port, sourceIp: srcIp, sourcePort: srcPort)
        return getConnectionByKey(key: key)
    }
    
    func getConnectionByKey(key: String) -> Connection? {
        return table[key]
    }
    
    func createTCPConnection(ip: UInt32, port: UInt16, srcIp: UInt32, srcPort: UInt16) -> Connection {
        let key = Connection.getConnectionKey(nwProtocol: .TCP, destIp: ip, destPort: port, sourceIp: srcIp, sourcePort: srcPort)

        if let existingConnection = table[key] {
            return existingConnection
        }

        let connection = Connection(nwProtocol: .TCP, sourceIp: srcIp, sourcePort: srcPort, destinationIp: ip, destinationPort: port, connectionCloser: self)

        let ipString = PacketUtil.intToIPAddress(ip)

        let endpoint: NWEndpoint
        if (proxyAddress == nil || !defaultPorts.contains(port) || isPrivateIP(ipString)) {
            endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ipString), port: NWEndpoint.Port(rawValue: port)!)
            // 使用 TCP 协议
            let parameters = NWParameters.tcp
            let nwConnection = NWConnection(to: endpoint, using: parameters)
            connection.channel = nwConnection
            connection.isInitConnect = true
        }

        self.table[key] = connection
        os_log("Created TCP connection %{public}@", log: OSLog.default, type: .default, key)

        return connection
    }

    private func isPrivateIP(_ ip: String) -> Bool {
        return ip.hasPrefix("10.") ||
               ip.hasPrefix("172.") && (16...31).contains(Int(ip.split(separator: ".")[1]) ?? -1) ||
               ip.hasPrefix("192.168.")
    }

    func createUDPConnection(ip: UInt32, port: UInt16, srcIp: UInt32, srcPort: UInt16) -> Connection {
        let key = Connection.getConnectionKey(nwProtocol: .UDP, destIp: ip, destPort: port, sourceIp: srcIp, sourcePort: srcPort)

        if let existingConnection = table[key] {
            return existingConnection
        }

       let connection = Connection(nwProtocol: .UDP, sourceIp: srcIp, sourcePort: srcPort, destinationIp: ip, destinationPort: port, connectionCloser: self)
     
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host((PacketUtil.intToIPAddress(ip))), port: NWEndpoint.Port(rawValue: port)!)

        let nwConnection = NWConnection(to: endpoint, using: .udp)
        connection.channel = nwConnection

        os_log("Created UDP connection %{public}@", log: OSLog.default, type: .default, key)
        self.table[key] = connection

        return connection
    }
    
    func closeConnection(connection: Connection) {
        closeConnection(
            nwProtocol: connection.nwProtocol, ip: connection.destinationIp, port: connection.destinationPort,
            srcIp: connection.sourceIp, srcPort: connection.sourcePort
        )
    }
    
    // 从内存中删除连接，然后关闭套接字。
    func closeConnection(nwProtocol: NWProtocol, ip: UInt32, port: UInt16, srcIp: UInt32, srcPort: UInt16) {
        let key = Connection.getConnectionKey(nwProtocol: nwProtocol, destIp: ip, destPort: port, sourceIp: srcIp, sourcePort: srcPort)
       
        if let connection = self.table.removeValue(forKey: key) {
            if connection.channel?.state != .cancelled {
                connection.channel?.cancel()
                os_log("Closed connection %{public}@", log: OSLog.default, type: .debug, key)
            } else {
                os_log("Connection %{public}@ is already cancelled", log: OSLog.default, type: .debug, key)
            }
        }
    }
    
    //添加来自客户端的数据，该数据稍后将在接收到PSH标志时发送到目的服务器。
    func addClientData(data: Data, connection: Connection)  {
        guard data.count > 0 else {
            return
        }
        
        connection.addSendData(data: data)
    }

    func keepSessionAlive(connection: Connection) {
        let key = Connection.getConnectionKey(
            nwProtocol: connection.nwProtocol,
            destIp: connection.destinationIp,
            destPort: connection.destinationPort,
            sourceIp: connection.sourceIp,
            sourcePort: connection.sourcePort
        )

        self.table[key] = connection
    }
}
