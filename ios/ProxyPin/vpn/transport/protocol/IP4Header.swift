//
//  IP4Header.swift
//  ProxyPin
//
//  Created by wanghongen on 2024/9/16.
//

import Foundation
import os.log

// IPv4 header data structure
class IP4Header {
    var ipVersion: UInt8 // 对于IPv4，其值为4（因此命名为IPv4）。 4bit
    var internetHeaderLength: UInt8 // 头部长度 4bit
    var diffTypeOfService: UInt8 // 差分服务代码点 =>6位
    var ecn: UInt8 // 显式拥塞通知（ECN）
    var totalLength: UInt16 // 此IP数据包的总长度 16bit
    var identification: UInt16 // 主要用于唯一标识单个IP数据报的片段组。 16bit
    var mayFragment: Bool // 用于指示数据报是否可以分段。 1bit
    var lastFragment: Bool // 用于指示数据报是否是片段中的最后一个。 1bit
    var fragmentOffset: UInt16 // 指定特定片段相对于原始未分段的IP数据报的开始的偏移量。 13bit
    var timeToLive: UInt8 // 用于防止数据报持续存在。8bit
    var protocolNumber: UInt8 // 定义IP数据报的数据部分中使用的协议。 8bit
    var headerChecksum: UInt16 // 用于对头部进行错误检查的16位字段。 16bit
    var sourceIP: UInt32 // 发送者的IPv4地址。 32bit
    var destinationIP: UInt32 // 接收者的IPv4地址。 32bit

    //用于控制或识别片段的3比特字段。
    //bit 0: 保留；必须为零
    //bit 1: Don't Fragment (DF)
    //bit 2: More Fragments (MF)
    private var flag: UInt8

    init(
        ipVersion: UInt8, internetHeaderLength: UInt8, diffTypeOfService: UInt8, ecn: UInt8, totalLength: UInt16, identification: UInt16,
        mayFragment: Bool, lastFragment: Bool, fragmentOffset: UInt16, timeToLive: UInt8, protocolNumber: UInt8, headerChecksum: UInt16,
        sourceIP: UInt32, destinationIP: UInt32
    ) {
        self.ipVersion = ipVersion
        self.internetHeaderLength = internetHeaderLength
        self.diffTypeOfService = diffTypeOfService
        self.ecn = ecn
        self.totalLength = totalLength
        self.identification = identification
        self.mayFragment = mayFragment
        self.lastFragment = lastFragment
        self.fragmentOffset = fragmentOffset
        self.timeToLive = timeToLive
        self.protocolNumber = protocolNumber
        self.headerChecksum = headerChecksum
        self.sourceIP = sourceIP
        self.destinationIP = destinationIP
        self.flag = IP4Header.initFlag(mayFragment: mayFragment, lastFragment: lastFragment)
    }


    private static func initFlag(mayFragment: Bool, lastFragment: Bool) -> UInt8 {
        var initFlag: UInt8 = 0
        if mayFragment {
          initFlag = 0x40
        }
        if lastFragment {
          initFlag |= 0x20
        }
        return initFlag
    }

    func setMayFragment(_ mayFragment: Bool) {
        self.mayFragment = mayFragment
        flag = mayFragment ? (flag | 0x40) : (flag & 0xBF)
    }

    func getIPHeaderLength() -> Int {
        return Int(internetHeaderLength * 4)
    }

    func copy() -> IP4Header {
       return IP4Header(
           ipVersion: ipVersion, internetHeaderLength: internetHeaderLength, diffTypeOfService: diffTypeOfService, ecn: ecn, totalLength: totalLength, identification: identification,
           mayFragment: mayFragment, lastFragment: lastFragment, fragmentOffset: fragmentOffset, timeToLive: timeToLive, protocolNumber: protocolNumber, headerChecksum: headerChecksum,
           sourceIP: sourceIP, destinationIP: destinationIP
       )
    }

    func toBytes() -> Data {
        var buffer = Data()
        buffer.append(UInt8((ipVersion << 4) + internetHeaderLength))
        buffer.append(UInt8((diffTypeOfService << 2) + ecn))

        buffer.append(contentsOf: totalLength.bytes)
        buffer.append(contentsOf: identification.bytes)

        //组合标志和部分片段偏移
        buffer.append(UInt8((fragmentOffset >> 8) & 0x1F) | flag)
        buffer.append(UInt8(fragmentOffset & 0xFF))

        buffer.append(timeToLive)
        buffer.append(protocolNumber)

        buffer.append(contentsOf: headerChecksum.bytes)

        buffer.append(contentsOf: sourceIP.bytes)
        buffer.append(contentsOf: destinationIP.bytes)
        return buffer
    }
}

class IPPacketFactory {
   static let IP4_HEADER_SIZE = 20
   static let IP4_VERSION: UInt8 = 0x04

   //从给定的ByteBuffer流创建IPv4标头
   static func createIP4Header(data: Data) -> IP4Header? {
       guard data.count >= IP4_HEADER_SIZE else {
           return nil
       }

       let buffer = [UInt8](data)
       let versionAndHeaderLength = buffer[0]
       let ipVersion = versionAndHeaderLength >> 4
       guard ipVersion == IP4_VERSION else {
           return nil
       }

       let internetHeaderLength = versionAndHeaderLength & 0x0F
       let headerLength = Int(internetHeaderLength) * 4
       guard internetHeaderLength >= 5, headerLength <= data.count else {
           os_log("Invalid IPv4 header length: %d, packet length: %d", log: OSLog.default, type: .error, headerLength, data.count)
           return nil
       }

       let typeOfService = buffer[1]
       let diffTypeOfService = typeOfService >> 2
       let ecn = typeOfService & 0x03
       let totalLength = UInt16(buffer[2]) << 8 | UInt16(buffer[3])
       let identification = UInt16(buffer[4]) << 8 | UInt16(buffer[5])
       let flagsAndFragmentOffset = UInt16(buffer[6]) << 8 | UInt16(buffer[7])
       let mayFragment = (flagsAndFragmentOffset & 0x4000) != 0
       let lastFragment = (flagsAndFragmentOffset & 0x2000) != 0
       let fragmentOffset = flagsAndFragmentOffset & 0x1FFF
       let timeToLive = buffer[8]
       let protocolNumber = buffer[9]
       let checksum = UInt16(buffer[10]) << 8 | UInt16(buffer[11])
       let sourceIp = UInt32(buffer[12]) << 24 | UInt32(buffer[13]) << 16 | UInt32(buffer[14]) << 8 | UInt32(buffer[15])
       let desIp = UInt32(buffer[16]) << 24 | UInt32(buffer[17]) << 16 | UInt32(buffer[18]) << 8 | UInt32(buffer[19])

       if internetHeaderLength > 5 {
           // drop the IP option
           for _ in 0..<(internetHeaderLength - 5) {
               // Skip the IP options
           }
       }

       return IP4Header(
           ipVersion: ipVersion, internetHeaderLength: internetHeaderLength, diffTypeOfService: diffTypeOfService, ecn: ecn, totalLength: totalLength, identification: identification,
           mayFragment: mayFragment, lastFragment: lastFragment, fragmentOffset: fragmentOffset, timeToLive: timeToLive, protocolNumber: protocolNumber, headerChecksum: checksum,
           sourceIP: sourceIp, destinationIP: desIp
       )
   }

   public static func printPacket(data: Data) {
       guard let ipHeader = createIP4Header(data: data) else {
           return
       }
       os_log("IP Header: version: %{public}d, internetHeaderLength: %{public}d, diffTypeOfService: %{public}d, ecn: %{public}d, totalLength: %{public}d, identification: %{public}d, mayFragment: %{public}d, lastFragment: %{public}d, fragmentOffset: %{public}d, timeToLive: %{public}d, protocolNumber: %{public}d, headerChecksum: %{public}d, sourceIP: %{public}@, destinationIP: %{public}@", log: OSLog.default, type: .default, ipHeader.ipVersion, ipHeader.internetHeaderLength, ipHeader.diffTypeOfService, ipHeader.ecn, ipHeader.totalLength, ipHeader.identification, ipHeader.mayFragment, ipHeader.lastFragment, ipHeader.fragmentOffset, ipHeader.timeToLive, ipHeader.protocolNumber, ipHeader.headerChecksum,  PacketUtil.intToIPAddress(ipHeader.sourceIP),  PacketUtil.intToIPAddress(ipHeader.destinationIP))
   }
}
