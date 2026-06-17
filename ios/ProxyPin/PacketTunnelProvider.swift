//
//  PacketTunnelProvider.swift
//  ProxyPin
//
//  Created by 汪红恩 on 2023/7/4.
//

import NetworkExtension
import Network
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var proxyVpnService: ProxyVpnService?

    private static func isIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else {
            return false
        }
        return parts.allSatisfy { part in
            guard let number = Int(part), number >= 0, number <= 255 else {
                return false
            }
            return String(number) == part
        }
    }

    private static func makeError(_ message: String) -> NSError {
        return NSError(domain: "ProxyPin.PacketTunnelProvider", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("startTunnel")

        guard let tunnelProtocol = protocolConfiguration as? NETunnelProviderProtocol else {
            let error = Self.makeError("Invalid tunnel protocol configuration")
            NSLog("[ERROR] \(error.localizedDescription)")
            completionHandler(error)
            return
        }
        guard let conf = tunnelProtocol.providerConfiguration else {
            let error = Self.makeError("No ProtocolConfiguration Found")
            NSLog("[ERROR] \(error.localizedDescription)")
            completionHandler(error)
            return
        }

        guard let host = conf["proxyHost"] as? String, !host.isEmpty else {
            let error = Self.makeError("Missing proxyHost")
            NSLog("[ERROR] \(error.localizedDescription)")
            completionHandler(error)
            return
        }
        guard let proxyPort = conf["proxyPort"] as? Int,
              proxyPort > 0,
              proxyPort <= Int(UInt16.max),
              let nwProxyPort = NWEndpoint.Port(rawValue: UInt16(proxyPort)) else {
            let error = Self.makeError("Invalid proxyPort")
            NSLog("[ERROR] \(error.localizedDescription)")
            completionHandler(error)
            return
        }
        let ipProxy = conf["ipProxy"] as? Bool ?? false

        // parse proxyPassDomains: accept either [String] or comma-separated String
        var proxyPassDomains: [String]? = nil
        if let arr = conf["proxyPassDomains"] as? [String] {
            proxyPassDomains = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } else if let csv = conf["proxyPassDomains"] as? String {
            let list = csv.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            proxyPassDomains = list.isEmpty ? nil : list
        }

//        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: host)
        NSLog(conf.debugDescription)

        networkSettings.mtu = 1500

        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.255"])

        if (ipProxy){
            ipv4Settings.includedRoutes = [NEIPv4Route.default()]
            var excludedRoutes = [
                NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
                NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
                NEIPv4Route(destinationAddress: "224.0.0.0", subnetMask: "240.0.0.0"),
                NEIPv4Route(destinationAddress: "240.0.0.0", subnetMask: "240.0.0.0"),
            ]
            if Self.isIPv4Address(host) {
                excludedRoutes.append(NEIPv4Route(destinationAddress: host, subnetMask: "255.255.255.255"))
            } else {
                NSLog("[WARN] proxyHost is not an IPv4 address, cannot add excluded route: \(host)")
            }
            ipv4Settings.excludedRoutes = excludedRoutes

        }

        //http代理
        let proxySettings = NEProxySettings()
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: host, port: proxyPort)
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: host, port: proxyPort)
        // If a proxyPassDomains list was provided, use it as the exceptionList so these domains bypass the proxy.
        if let pass = proxyPassDomains {
            proxySettings.exceptionList = pass
        }

        proxySettings.matchDomains = [""]
        networkSettings.proxySettings =  proxySettings

        networkSettings.ipv4Settings = ipv4Settings

        setTunnelNetworkSettings(networkSettings) { error in
           guard error == nil else {
               NSLog("startTunnel Encountered an error setting up the network: \(error.debugDescription)")
               completionHandler(error)
               return
           }

           if (ipProxy){
             let proxyAddress =  Network.NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwProxyPort)
             self.proxyVpnService = ProxyVpnService(packetFlow: self.packetFlow, proxyAddress: proxyAddress)
             self.proxyVpnService!.start()
           }
           completionHandler(nil)
       }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        proxyVpnService?.stop()
        proxyVpnService = nil
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Add code here to handle the message.
        if let handler = completionHandler {
            NSLog("handleAppMessage ", messageData.debugDescription)
            handler(messageData)
        }
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        // Add code here to get ready to sleep.
        completionHandler()
    }

    override func wake() {
        // Add code here to wake up.
    }
}
