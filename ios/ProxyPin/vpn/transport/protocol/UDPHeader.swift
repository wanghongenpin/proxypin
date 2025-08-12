//
//  UDPHeader.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/17.
//

import Foundation
import os.log

///UDP报头的数据
struct UDPHeader {
    var sourcePort: UInt16  //源端口号 16bit
    var destinationPort: UInt16  //源端口号 16bit
    var length: UInt16  //UDP数据报长度 16bit
    var checksum: UInt16 //校验和 16bit

    init(sourcePort: UInt16, destinationPort: UInt16, length: UInt16, checksum: UInt16) {
        self.sourcePort = sourcePort
        self.destinationPort = destinationPort
        self.length = length
        self.checksum = checksum
    }
}

class UDPPacketFactory {
    static let UDP_HEADER_LENGTH = 8
    
    static func createUDPHeader(from data: Data) -> UDPHeader? {
        guard data.count >= UDP_HEADER_LENGTH else {
            return nil
        }

        let srcPort = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self).bigEndian }
        let destPort = data.withUnsafeBytes { $0.load(fromByteOffset: 2, as: UInt16.self).bigEndian }
        let length = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt16.self).bigEndian }
        let checksum = data.withUnsafeBytes { $0.load(fromByteOffset: 6, as: UInt16.self).bigEndian }

        return UDPHeader(sourcePort: srcPort, destinationPort: destPort, length: length, checksum: checksum)
    }
    

    //
    static func createResponsePacket(ip: IP4Header, udp: UDPHeader, packetData: Data?) -> Data {
        var udpLen = 8
        if let packetData = packetData {
            udpLen += packetData.count
        }
        
        let srcPort = udp.destinationPort
        let destPort = udp.sourcePort

        let ipHeader = ip.copy()
        let srcIp = ip.destinationIP
        let destIp = ip.sourceIP

        ipHeader.setMayFragment(false)
        ipHeader.sourceIP = srcIp
        ipHeader.destinationIP = destIp
        ipHeader.identification = UInt16(truncatingIfNeeded: PacketUtil.getPacketId())

        //ip的长度是整个数据包的长度 => IP header length + UDP header length (8) + UDP body length
        let totalLength = ipHeader.getIPHeaderLength() + udpLen
        ipHeader.totalLength = UInt16(totalLength)

        var ipData = ipHeader.toBytes()
        
        // clear IP checksum
        ipData.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) in
            bytes[10] = 0
            bytes[11] = 0
        }

        // calculate checksum for IP header
        let ipChecksum = PacketUtil.calculateChecksum(data: ipData, offset: 0, length: ipData.count)

        // write result of checksum back to buffer
        ipData.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) in
            bytes[10] = ipChecksum[0]
            bytes[11] = ipChecksum[1]
        }

        var buffer = Data()

        // copy IP header to buffer
        buffer.append(ipData)

        // copy UDP header to buffer
        buffer.append(contentsOf: srcPort.bytes)
        buffer.append(contentsOf: destPort.bytes)
        buffer.append(contentsOf: UInt16(udpLen).bytes)

        // 计算UDP校验和
        let udpChecksum: UInt16 = 0
        buffer.append(contentsOf: udpChecksum.bytes)

        if let packetData = packetData {
            buffer.append(packetData)
        }
        return buffer
    }

}
