//
//  TCPPacketFactory.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/16.
//
//

import Foundation
import os.log

/// Factory class for creating TCP packets.
class TCPPacketFactory {

   public static let TCP_HEADER_LENGTH = 20

   //从tcp报文创建tcpHeader
    static func createTCPHeader(data: Data) -> TCPHeader? {
        if  data.count < TCP_HEADER_LENGTH {
            os_log("Data is too short to be a TCP packet", log: OSLog.default, type: .error)
            return nil
        }


        var offset = 0

        func readUInt16() -> UInt16 {
            let value = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2
            return value
        }

        func readUInt32() -> UInt32 {
            let value = UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
            offset += 4
            return value
        }

        let sourcePort = readUInt16()
        let destinationPort = readUInt16()

        let sequenceNumber = readUInt32()
        let ackNumber = readUInt32()

        let dataOffsetAndReserved = data[offset]
        offset += 1
        let dataOffset = UInt8((dataOffsetAndReserved & 0xF0) >> 4)
        let headerLength = Int(dataOffset) * 4
        guard dataOffset >= 5, headerLength <= data.count else {
            os_log("Invalid TCP data offset: %d, packet length: %d", log: OSLog.default, type: .error, dataOffset, data.count)
            return nil
        }

        let isNs = (dataOffsetAndReserved & 0x01) == 1
        let flags = UInt8(data[offset])
        offset += 1

        let windowSize = readUInt16()
        let checksum = readUInt16()
        let urgentPointer = readUInt16()

        let optionsSize = headerLength - TCP_HEADER_LENGTH
        var options: Data?
        if (optionsSize > 0) {
            options = data.subdata(in: offset..<offset + optionsSize)
        }
        offset = headerLength

        let payload: Data? = offset < data.count ? data.subdata(in: offset..<data.count) : nil
        return TCPHeader(
            sourcePort: sourcePort,
            destinationPort: destinationPort,
            sequenceNumber: sequenceNumber,
            ackNumber: ackNumber,
            dataOffset: dataOffset,
            isNS: isNs,
            flags: flags,
            windowSize: windowSize,
            checksum: checksum,
            urgentPointer: urgentPointer,
            options: options,
            payload: payload
        )
    }
    
    //向客户端确认服务器已收到请求
    static func createResponseAckData(ipHeader: IP4Header, tcpHeader: TCPHeader, ackToClient: UInt32) -> Data {
       var ip = ipHeader.copy()
       var tcp = tcpHeader.copy()

       flipIp(ip: &ip, tcp: &tcp)
       let seqNumber = tcp.ackNumber
       tcp.ackNumber = ackToClient
       tcp.sequenceNumber = seqNumber

        ip.identification = UInt16(truncatingIfNeeded: PacketUtil.getPacketId())

       // Set TCP flags
       tcp.setIsACK(true)
       tcp.setIsSYN(false)
       tcp.setIsPSH(false)
       tcp.setIsFIN(false)

       tcp.dataOffset = 5 // tcp header length 5 * 4 = 20 bytes
       tcp.options = nil

       ip.totalLength = UInt16(ip.getIPHeaderLength() + tcp.getTCPHeaderLength())
        
       return createPacketData(ipHeader: ip, tcpHeader: tcp, data: nil)
   }
    
    ///创建带有RST标志的数据包，以便在需要重置时发送到客户端。
    static func createRstData(ipHeader: IP4Header, tcpHeader: TCPHeader, dataLength: Int) -> Data {
        var ip = ipHeader.copy()
        var tcp = tcpHeader.copy()

        var ackNumber: UInt32 = 0
        var seqNumber: UInt32 = 0

        if tcp.ackNumber > 0 {
            seqNumber = tcp.ackNumber
        } else {
            ackNumber = tcp.sequenceNumber + UInt32(dataLength)
        }

        tcp.ackNumber = ackNumber
        tcp.sequenceNumber = seqNumber

        // Flip IP from source to destination
        flipIp(ip: &ip, tcp: &tcp)

        ip.identification = 0

        tcp.flags = 0
        tcp.isNS = false
        tcp.setIsRST(true)

        tcp.dataOffset = 5
        tcp.options = nil
        tcp.windowSize = 0

        // Recalculate IP length
        let totalLength = ip.getIPHeaderLength() + tcp.getTCPHeaderLength()
        ip.totalLength = UInt16(totalLength)

        return createPacketData(ipHeader: ip, tcpHeader: tcp, data: nil)
    }
    
    //创建发送到客户端的FIN-ACK
    static func createFinAckData(ipHeader: IP4Header, tcpHeader: TCPHeader, ackToClient: UInt32, seqToClient: UInt32, isFin: Bool, isAck: Bool) -> Data {
        var ip = ipHeader.copy()
        var tcp = tcpHeader.copy()

        flipIp(ip: &ip, tcp: &tcp)

        tcp.dataOffset = 5 // tcp header length 5 * 4 = 20 bytes
        tcp.options = nil

        tcp.ackNumber = ackToClient
        tcp.sequenceNumber = seqToClient
        ip.identification = UInt16(truncatingIfNeeded: PacketUtil.getPacketId())

        tcp.setIsACK(isAck)
        tcp.setIsSYN(false)
        tcp.setIsPSH(false)
        tcp.setIsFIN(isFin)

        ip.totalLength = UInt16(ip.getIPHeaderLength() + tcp.getTCPHeaderLength())
        return createPacketData(ipHeader: ip, tcpHeader: tcp, data: nil)
    }

   //通过写回客户端流创建SYN-ACK数据包数据
   public static func createSynAckPacketData(ipHeader: IP4Header, tcpHeader: TCPHeader) -> Packet {
       var ip = ipHeader.copy()
       var tcp = tcpHeader.copy()
       flipIp(ip: &ip, tcp: &tcp)

       tcp.dataOffset = 5 // tcp header length 5 * 4 = 20 bytes
       tcp.options = nil

       // ack = received sequence + 1
       let ackNumber = tcpHeader.sequenceNumber + 1
       tcp.ackNumber = ackNumber

       // Server-generated initial sequence number
       let seqNumber = UInt64.random(in: 0..<100000)
       tcp.sequenceNumber = UInt32(seqNumber)

       // SYN-ACK
       tcp.setIsACK(true)
       tcp.setIsSYN(true)

       tcp.timeStampReplyTo = tcp.timeStampSender
       tcp.timeStampSender = PacketUtil.currentTime

       ip.totalLength = UInt16(ip.getIPHeaderLength() + tcp.getTCPHeaderLength())

       return Packet(ipHeader: ip, transportHeader: tcp, buffer: createPacketData(ipHeader: ip, tcpHeader: tcp, data: nil))
   }

    //创建数据包数据以发送回客户端
   public static func createResponsePacketData(
        ipHeader: IP4Header, tcpHeader: TCPHeader, packetData: Data?, isPsh: Bool,
        ackNumber: UInt32, seqNumber: UInt32, timeSender: Int, timeReplyTo: Int
    ) -> Data {
        var ip = ipHeader.copy()
        var tcp = tcpHeader.copy()

        flipIp(ip: &ip, tcp: &tcp)

        tcp.dataOffset = 5 // tcp header length 5 * 4 = 20 bytes
        tcp.options = nil

        tcp.ackNumber = ackNumber
        tcp.sequenceNumber = seqNumber
        ip.identification = UInt16(truncatingIfNeeded: PacketUtil.getPacketId())

        // ACK is always sent
        tcp.setIsACK(true)
        tcp.setIsSYN(false)
        tcp.setIsPSH(isPsh)
        tcp.setIsFIN(false)
        tcp.timeStampSender = timeSender
        tcp.timeStampReplyTo = timeReplyTo

        var totalLength = ip.getIPHeaderLength() + tcp.getTCPHeaderLength()
        if let packetData = packetData {
            totalLength += packetData.count
        }
        ip.totalLength = UInt16(totalLength)

        return createPacketData(ipHeader: ip, tcpHeader: tcp, data: packetData)
    }

    //将IP从源翻转到目标
    private static func flipIp(ip: inout IP4Header, tcp: inout TCPHeader) {
       let sourceIp = ip.destinationIP
       let destIp = ip.sourceIP
       let sourcePort = tcp.destinationPort
       let destPort = tcp.sourcePort

       ip.destinationIP = destIp
       ip.sourceIP = sourceIp
       tcp.destinationPort = destPort
       tcp.sourcePort = sourcePort
    }

    public static func createFinData(
        ipHeader: IP4Header, tcpHeader: TCPHeader, ackNumber: UInt32, seqNumber: UInt32,
        timeSender: Int, timeReplyTo: Int
    ) -> Data {
        var ip = ipHeader.copy()
        var tcp = tcpHeader.copy()

        flipIp(ip: &ip, tcp: &tcp)

        tcp.ackNumber = ackNumber
        tcp.sequenceNumber = seqNumber

        ip.identification = UInt16(truncatingIfNeeded: PacketUtil.getPacketId())

        tcp.timeStampReplyTo = timeReplyTo
        tcp.timeStampSender = timeSender

        tcp.flags = 0
        tcp.isNS = false
        tcp.setIsACK(true)
        tcp.setIsFIN(true)

        tcp.options = nil
        tcp.windowSize = 0

        ip.totalLength = UInt16(ip.getIPHeaderLength() + TCP_HEADER_LENGTH)
        return createPacketData(ipHeader: ip, tcpHeader: tcp, data: nil)
    }
    

    //从tcpHeader创建tcp报文
    private static func createPacketData(ipHeader: IP4Header, tcpHeader: TCPHeader, data: Data?) -> Data {
       let dataLength = data?.count ?? 0

       var buffer = Data()

       // Add IP header
       let ipBuffer = ipHeader.toBytes()
       buffer.append(ipBuffer)

       // Add TCP header
       let tcpBuffer = tcpHeader.toBytes()
       buffer.append(tcpBuffer)

       // Add data if exists
       if let data = data {
           buffer.append(data)
       }

       // Zero out IP checksum
       buffer[10] = 0
       buffer[11] = 0

       // Calculate IP checksum
       let ipChecksum = PacketUtil.calculateChecksum(data: buffer, offset: 0, length: ipBuffer.count)
       buffer[10] = ipChecksum[0]
       buffer[11] = ipChecksum[1]
//       IPPacketFactory.printPacket(data: ipBuffer)

       // Zero out TCP checksum
       let tcpStart = ipBuffer.count
       buffer[tcpStart + 16] = 0
       buffer[tcpStart + 17] = 0

       // Calculate TCP checksum
       let tcpChecksum = PacketUtil.calculateTCPHeaderChecksum(
        data: buffer, offset: tcpStart, tcpLength: tcpBuffer.count + dataLength,
           sourceIP: ipHeader.sourceIP, destinationIP: ipHeader.destinationIP
       )
       buffer[tcpStart + 16] = tcpChecksum[0]
       buffer[tcpStart + 17] = tcpChecksum[1]
       return buffer
   }

    static func printPacket(data: Data) {
        guard let tcpHeader = createTCPHeader(data: data) else {
            os_log("Failed to create TCP header", log: OSLog.default, type: .error)
            return
        }

        os_log("TCP Header: sourcePort: %{public}d, destinationPort: %{public}d, sequenceNumber: %{public}u, ackNumber: %{public}u, dataOffset: %{public}d, isNS: %{public}d, flags: %{public}d, windowSize: %{public}d, checksum: %{public}u, urgentPointer: %{public}u",
               log: OSLog.default, type: .default, tcpHeader.sourcePort, tcpHeader.destinationPort, tcpHeader.sequenceNumber, tcpHeader.ackNumber, tcpHeader.dataOffset, tcpHeader.isNS ? 1 : 0, tcpHeader.flags, tcpHeader.windowSize, tcpHeader.checksum, tcpHeader.urgentPointer)
    }
}
