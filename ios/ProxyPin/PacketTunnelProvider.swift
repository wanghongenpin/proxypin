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
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        NSLog("startTunnel")

        guard let conf = (protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration else{
            NSLog("[ERROR] No ProtocolConfiguration Found")
            exit(EXIT_FAILURE)
        }

        let host = conf["proxyHost"] as! String
        let proxyPort = conf["proxyPort"] as! Int
        let ipProxy = conf["ipProxy"] as! Bool? ?? false

//        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: host)
        NSLog(conf.debugDescription)
     
        networkSettings.mtu = 1500
        
        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.255"])
       
        if (ipProxy){
            ipv4Settings.includedRoutes = [NEIPv4Route.default()]
           ipv4Settings.excludedRoutes = [
               NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
               NEIPv4Route(destinationAddress: "100.64.0.0", subnetMask: "255.192.0.0"),
//                NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
               NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
               NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
               NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
               NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"),
           ]
            
           let dns = "223.5.5.5,8.8.8.8"
           let dnsSettings = NEDNSSettings(servers: dns.components(separatedBy: ","))
           dnsSettings.matchDomains = [""]
           dnsSettings.matchDomainsNoSearch = true
           networkSettings.dnsSettings = dnsSettings
        }
        
        //http代理
        let proxySettings = NEProxySettings()
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: host, port: proxyPort)
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: host, port: proxyPort)
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
             let proxyAddress =  Network.NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(proxyPort))!)
             self.proxyVpnService = ProxyVpnService(packetFlow: self.packetFlow, proxyAddress: proxyAddress)
             self.proxyVpnService!.start()
           }
           completionHandler(nil)
       }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        proxyVpnService?.stop()
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
