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
    private let lock = NSLock()

    public var proxyAddress: NWEndpoint?

    private let defaultPorts: [UInt16] = [80, 443, 8080, 8088, 8888, 9000]
    private let maxConnections = 384
    private let tcpSessionTimeout: TimeInterval = 30
    private let udpSessionTimeout: TimeInterval = 10
    private let dnsSessionTimeout: TimeInterval = 3
    
   
    func getConnection(nwProtocol: NWProtocol, ip: UInt32, port: UInt16, srcIp: UInt32, srcPort: UInt16) -> Connection? {
        let key = Connection.getConnectionKey(nwProtocol: nwProtocol, destIp: ip, destPort: port, sourceIp: srcIp, sourcePort: srcPort)
        return getConnectionByKey(key: key)
    }
    
    func getConnectionByKey(key: String) -> Connection? {
        lock.lock()
        let connection = table[key]
        lock.unlock()
        connection?.withLock {
            connection?.lastActiveAt = Date()
        }
        return connection
    }

    func createTCPConnection(ip: UInt32, port: UInt16, srcIp: UInt32, srcPort: UInt16) -> Connection {
        let key = Connection.getConnectionKey(nwProtocol: .TCP, destIp: ip, destPort: port, sourceIp: srcIp, sourcePort: srcPort)

        let createdConnection: Connection
        var shouldScheduleCleanup = false
        var shouldLogCreated = false

        lock.lock()
        if let existingConnection = table[key] {
            lock.unlock()
            existingConnection.withLock {
                existingConnection.lastActiveAt = Date()
            }
            return existingConnection
        }
        reapIdleConnections(keepingCapacityFor: key)

        let connection = Connection(nwProtocol: .TCP, sourceIp: srcIp, sourcePort: srcPort, destinationIp: ip, destinationPort: port, connectionCloser: self)
        let ipString = PacketUtil.intToIPAddress(ip)
        if (proxyAddress == nil || !defaultPorts.contains(port) || isPrivateIP(ipString)) {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ipString), port: NWEndpoint.Port(rawValue: port)!)
            let nwConnection = NWConnection(to: endpoint, using: .tcp)
            connection.withLock {
                connection.channel = nwConnection
                connection.isInitConnect = true
            }
        }

        self.table[key] = connection
        createdConnection = connection
        shouldScheduleCleanup = true
        shouldLogCreated = true
        lock.unlock()

        if shouldScheduleCleanup {
            scheduleCleanup(connection: createdConnection)
        }
        if shouldLogCreated {
            os_log("Created TCP connection %{public}@", log: OSLog.default, type: .default, key)
        }

        return createdConnection
    }

    private func isPrivateIP(_ ip: String) -> Bool {
        return ip.hasPrefix("10.") ||
               ip.hasPrefix("172.") && (16...31).contains(Int(ip.split(separator: ".")[1]) ?? -1) ||
               ip.hasPrefix("192.168.")
    }

    func createUDPConnection(ip: UInt32, port: UInt16, srcIp: UInt32, srcPort: UInt16) -> Connection {
        let key = Connection.getConnectionKey(nwProtocol: .UDP, destIp: ip, destPort: port, sourceIp: srcIp, sourcePort: srcPort)

        let createdConnection: Connection

        lock.lock()
        if let existingConnection = table[key] {
            lock.unlock()
            existingConnection.withLock {
                existingConnection.lastActiveAt = Date()
            }
            return existingConnection
        }
        reapIdleConnections(keepingCapacityFor: key)

       let connection = Connection(nwProtocol: .UDP, sourceIp: srcIp, sourcePort: srcPort, destinationIp: ip, destinationPort: port, connectionCloser: self)

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host((PacketUtil.intToIPAddress(ip))), port: NWEndpoint.Port(rawValue: port)!)

        let nwConnection = NWConnection(to: endpoint, using: .udp)
        connection.withLock {
            connection.channel = nwConnection
        }

        self.table[key] = connection
        createdConnection = connection
        lock.unlock()

        os_log("Created UDP connection %{public}@", log: OSLog.default, type: .default, key)
        scheduleCleanup(connection: createdConnection)

        return createdConnection
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
       
        lock.lock()
        let connection = self.table.removeValue(forKey: key)
        lock.unlock()

        if let connection = connection {
            let channel = connection.takeChannelForClose()
            if channel?.state != .cancelled {
                channel?.cancel()
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

        connection.withLock {
            connection.lastActiveAt = Date()
        }
        lock.lock()
        self.table[key] = connection
        lock.unlock()
    }

    private func timeout(for connection: Connection) -> TimeInterval {
        if connection.nwProtocol == .UDP && connection.destinationPort == 53 {
            return dnsSessionTimeout
        }
        return connection.nwProtocol == .UDP ? udpSessionTimeout : tcpSessionTimeout
    }

    private func scheduleCleanup(connection: Connection) {
        let timeout = timeout(for: connection)
        let workItem = DispatchWorkItem { [weak self, weak connection] in
            guard let self = self, let connection = connection else { return }
            self.closeIfIdle(connection: connection, timeout: timeout)
        }
        connection.scheduleCleanup(workItem)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func closeIfIdle(connection: Connection, timeout: TimeInterval) {
        let idleTime = connection.idleTime
        guard idleTime >= timeout else {
            scheduleCleanup(connection: connection)
            return
        }

        os_log("Connection %{public}@ idle for %.1fs, closing", log: OSLog.default, type: .debug, connection.description, idleTime)
        closeConnection(connection: connection)
    }

    private func reapIdleConnections(keepingCapacityFor newKey: String) {
        guard table.count >= maxConnections else {
            return
        }

        let now = Date()
        let expired = table.filter { _, connection in
            let timeout = timeout(for: connection)
            return connection.withLock { now.timeIntervalSince(connection.lastActiveAt) >= timeout }
        }

        for (key, connection) in expired {
            table.removeValue(forKey: key)
            connection.takeChannelForClose()?.cancel()
        }

        if table.count >= maxConnections,
           let oldest = table.min(by: { left, right in
               left.value.withLock { left.value.lastActiveAt } < right.value.withLock { right.value.lastActiveAt }
           }) {
            table.removeValue(forKey: oldest.key)
            oldest.value.takeChannelForClose()?.cancel()
            os_log("Connection table full, evicted oldest connection %{public}@ for %{public}@", log: OSLog.default, type: .error, oldest.key, newKey)
        }
    }
}
