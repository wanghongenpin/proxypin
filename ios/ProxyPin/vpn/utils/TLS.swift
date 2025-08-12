//
//  TLS.swift
//  Runner
//
//  Created by wanghongen on 2025/5/31.
//

class TLS {
    
    static func isTLSClientHello(packetData: Data) -> Bool {
        // Ensure the packet has enough data for a TLS ClientHello message
        guard packetData.count >= 43 else {
            return false
        }

        // Check if the first byte is 0x16 (Handshake type: ClientHello)
        if packetData[0] != 0x16 {
            return false
        }

        // Check if the next two bytes represent a valid TLS version (e.g., 0x0301, 0x0302, 0x0303)
        let version = packetData[1...2]
        if version != Data([0x03, 0x01]) && version != Data([0x03, 0x02]) && version != Data([0x03, 0x03]) {
            return false
        }

        // Check if the handshake message type is ClientHello (0x01)
        if packetData[5] != 0x01 {
            return false
        }

        // Check if the record layer protocol version matches the expected TLS version
        let recordVersion = packetData[9...10]
        if recordVersion != Data([0x03, 0x01]) && recordVersion != Data([0x03, 0x02]) && recordVersion != Data([0x03, 0x03]) {
            return false
        }

        return true
    }
}
