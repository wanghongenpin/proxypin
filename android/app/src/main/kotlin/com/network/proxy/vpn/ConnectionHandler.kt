package com.network.proxy.vpn

import android.util.Log
import com.network.proxy.vpn.Connection.Companion.getConnectionKey
import com.network.proxy.vpn.socket.ClientPacketWriter
import com.network.proxy.vpn.socket.SocketNIODataService
import com.network.proxy.vpn.transport.icmp.ICMPPacket
import com.network.proxy.vpn.transport.icmp.ICMPPacketFactory
import com.network.proxy.vpn.transport.protocol.IP4Header
import com.network.proxy.vpn.transport.protocol.IPPacketFactory
import com.network.proxy.vpn.transport.protocol.TCPHeader
import com.network.proxy.vpn.transport.protocol.TCPPacketFactory
import com.network.proxy.vpn.transport.protocol.UDPPacketFactory
import com.network.proxy.vpn.util.PacketUtil.getOutput
import com.network.proxy.vpn.util.PacketUtil.intToIPAddress
import com.network.proxy.vpn.util.PacketUtil.isPacketCorrupted
import com.network.proxy.vpn.util.ProcessInfoManager
import com.network.proxy.vpn.util.TLS.isTLSClientHello
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.nio.ByteBuffer
import java.nio.channels.SelectionKey
import java.nio.channels.SocketChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

class ConnectionHandler(
    private val manager: ConnectionManager,
    private val nioService: SocketNIODataService,
    private val writer: ClientPacketWriter
) {

    private val pingThreadPool: ExecutorService = ThreadPoolExecutor(
        1, 20,  // 1 - 20 parallel pings max
        60L, TimeUnit.SECONDS,
        SynchronousQueue(),
        ThreadPoolExecutor.DiscardPolicy() // Replace running pings if there's too many
    )

    /**
     * Handle unknown raw IP packet data
     *
     * @param stream ByteBuffer to be read
     */
    @Throws(IOException::class)
    fun handlePacket(stream: ByteBuffer) {
        stream.rewind()

        val ipHeader = IPPacketFactory.createIP4Header(stream)

        if (ipHeader == null) {
            stream.rewind()
            Log.w(TAG, "Malformed IP packet ")
            return
        }
        if (ipHeader.protocol.toInt() == 6) {
            handleTCPPacket(stream, ipHeader)
        } else if (ipHeader.protocol.toInt() == 17) {
            handleUDPPacket(stream, ipHeader)
        } else if (ipHeader.protocol.toInt() == 1) {
            handleICMPPacket(stream, ipHeader)
        } else {
            Log.w(TAG, "Unsupported IP protocol: " + ipHeader.protocol)
        }
    }

    @Throws(IOException::class)
    private fun handleUDPPacket(clientPacketData: ByteBuffer, ipHeader: IP4Header) {
        val udpHeader = UDPPacketFactory.createUDPHeader(clientPacketData)
        var connection = manager.getConnection(
            Protocol.UDP,
            ipHeader.destinationIP, udpHeader.destinationPort,
            ipHeader.sourceIP, udpHeader.sourcePort
        )
        val newSession = connection == null
        if (connection == null) {
            connection = manager.createUDPConnection(
                ipHeader.destinationIP, udpHeader.destinationPort,
                ipHeader.sourceIP, udpHeader.sourcePort
            )
        }
        synchronized(connection) {
            connection.lastIpHeader = ipHeader
            connection.lastUdpHeader = udpHeader
            manager.addClientData(clientPacketData, connection)
            connection.isDataForSendingReady = true

            // We don't register the session until it's fully populated (as above)
            if (newSession) nioService.registerSession(connection)

            // Ping the NIO thread to write this, when the session is next writable
            connection.subscribeKey(SelectionKey.OP_WRITE)
            nioService.refreshSelect(connection)
        }
        manager.keepSessionAlive(connection)
    }

    /**
     * 是否支持协议
     */
    private val methods: List<String> =
        mutableListOf("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT", "PROPFIND", "REPORT")

    private fun supperProtocol(packetData: ByteBuffer): Boolean {
        val position = packetData.position()
        //判断是否是ssl握手
        if (isTLSClientHello(packetData)) {
            packetData.position(position)
            return true
        }
        packetData.position(position)
        for (method in methods) {
            if (packetData.remaining() < method.length) {
                continue
            }
            val bytes = ByteArray(method.length)
            for (i in bytes.indices) {
                bytes[i] = packetData[position + i]
            }
            if (method.equals(String(bytes), ignoreCase = true)) {
                return true
            }
        }
        return false
    }

    /**
     * 获取代理地址
     */
    private fun getProxyAddress(
        packetData: ByteBuffer, destinationIP: Int, destinationPort: Int
    ): InetSocketAddress {
        val ips = intToIPAddress(destinationIP)

        // 检查是否在代理过滤列表中
        if (shouldBypassProxy(ips)) {
            Log.d(TAG, "Bypassing proxy for $ips (in proxyPassDomains)")
            return InetSocketAddress(ips, destinationPort)
        }

        val supperProtocol = supperProtocol(packetData)
        var socketAddress: InetSocketAddress? = null
        if (supperProtocol) {
            socketAddress = manager.proxyAddress
        }
        if (socketAddress == null) {
            socketAddress = InetSocketAddress(ips, destinationPort)
        }
        return socketAddress
    }

    /**
     * 检查是否应该绕过代理
     * 支持 CIDR 格式（如 192.168.0.0/16）、IP地址、localhost 和域名（带通配符）匹配
     */
    private fun shouldBypassProxy(destinationIP: String): Boolean {
        val proxyPassDomains = manager.proxyPassDomains ?: return false

        for (domain in proxyPassDomains) {
            try {
                val trimmedDomain = domain.trim()

                // 处理 localhost
                if (trimmedDomain == "localhost" && (destinationIP == "127.0.0.1" || destinationIP == "localhost")) {
                    return true
                }

                // 处理 CIDR 格式，如 192.168.0.0/16
                if (trimmedDomain.contains("/")) {
                    if (matchesCIDR(destinationIP, trimmedDomain)) {
                        return true
                    }
                } else if (trimmedDomain.startsWith("*.")) {
                    // 支持通配符匹配，如 *.example.com
                    val suffix = trimmedDomain.substring(1) // 去掉 *
                    if (destinationIP.endsWith(suffix)) {
                        return true
                    }
                } else if (trimmedDomain.contains("*")) {
                    // 支持其他通配符模式
                    val pattern = trimmedDomain.replace(".", "\\.").replace("*", ".*")
                    if (destinationIP.matches(Regex(pattern))) {
                        return true
                    }
                } else {
                    // 精确匹配 IP 或域名
                    if (destinationIP == trimmedDomain) {
                        return true
                    }

                    // 尝试解析域名为IP地址进行比较
                    try {
                        val address = InetAddress.getByName(trimmedDomain)
                        if (address.hostAddress == destinationIP) {
                            return true
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Error resolving domain $trimmedDomain: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error matching domain $domain: ${e.message}")
            }
        }

        return false
    }

    /**
     * 检查 IP 地址是否匹配 CIDR 格式
     * @param ip 目标 IP 地址，如 "192.168.1.1"
     * @param cidr CIDR 格式，如 "192.168.0.0/16"
     * @return 是否匹配
     */
    private fun matchesCIDR(ip: String, cidr: String): Boolean {
        try {
            val parts = cidr.split("/")
            if (parts.size != 2) return false

            val networkAddress = parts[0]
            val prefixLength = parts[1].toIntOrNull() ?: return false

            val ipBytes = ipToBytes(ip)
            val networkBytes = ipToBytes(networkAddress)

            if (ipBytes == null || networkBytes == null) return false

            // 计算掩码
            val mask = (-1L shl (32 - prefixLength)).toInt()

            // 将 IP 地址转换为整数进行比较
            val ipInt = bytesToInt(ipBytes)
            val networkInt = bytesToInt(networkBytes)

            return (ipInt and mask) == (networkInt and mask)
        } catch (e: Exception) {
            Log.w(TAG, "Error matching CIDR $cidr for IP $ip: ${e.message}")
            return false
        }
    }

    /**
     * 将 IP 地址字符串转换为字节数组
     */
    private fun ipToBytes(ip: String): ByteArray? {
        try {
            val parts = ip.split(".")
            if (parts.size != 4) return null

            return ByteArray(4) { i ->
                parts[i].toInt().toByte()
            }
        } catch (_: Exception) {
            return null
        }
    }

    /**
     * 将字节数组转换为整数
     */
    private fun bytesToInt(bytes: ByteArray): Int {
        return ((bytes[0].toInt() and 0xFF) shl 24) or
               ((bytes[1].toInt() and 0xFF) shl 16) or
               ((bytes[2].toInt() and 0xFF) shl 8) or
               (bytes[3].toInt() and 0xFF)
    }

    @Throws(IOException::class)
    private fun handleTCPPacket(clientPacketData: ByteBuffer, ip4Header: IP4Header) {
        val tcpHeader = TCPPacketFactory.createTCPHeader(clientPacketData)
        val dataLength = clientPacketData.limit() - clientPacketData.position()
        val sourceIP = ip4Header.sourceIP
        val destinationIP = ip4Header.destinationIP
        val sourcePort = tcpHeader.getSourcePort()
        val destinationPort = tcpHeader.getDestinationPort()
        if (tcpHeader.isSYN()) {
            // 3-way handshake + create new session
            replySynAck(ip4Header, tcpHeader)
        } else if (tcpHeader.isACK()) {
            val key =
                getConnectionKey(Protocol.TCP, destinationIP, destinationPort, sourceIP, sourcePort)
            val connection = manager.getConnectionByKey(key)
            if (connection == null) {
                Log.w(TAG, "Ack for unknown session: $key")
                if (tcpHeader.isFIN()) {
                    sendLastAck(ip4Header, tcpHeader)
                } else if (!tcpHeader.isRST()) {
                    sendRstPacket(ip4Header, tcpHeader, dataLength)
                }
                return
            }
            synchronized(connection) {
                connection.lastIpHeader = ip4Header
                connection.lastTcpHeader = tcpHeader

                //any data from client?
                if (dataLength > 0) {
                    //init proxy
                    initProxyConnect(clientPacketData, destinationIP, destinationPort, connection)

                    //accumulate data from client
                    if (connection.recSequence == 0L || tcpHeader.sequenceNumber >= connection.recSequence) {
                        val addedLength = manager.addClientData(clientPacketData, connection)
                        //send ack to client only if new data was added
                        sendAck(ip4Header, tcpHeader, addedLength, connection)
                    } else {
                        sendAckForDisorder(ip4Header, tcpHeader, dataLength)
                    }
                } else {
                    //an ack from client for previously sent data
                    acceptAck(tcpHeader, connection)
                    if (connection.isClosingConnection) {
                        sendFinAck(ip4Header, tcpHeader, connection)
                    } else if (connection.isAckedToFin && !tcpHeader.isFIN()) {
                        //the last ACK from client after FIN-ACK flag was sent
                        manager.closeConnection(
                            Protocol.TCP,
                            destinationIP,
                            destinationPort,
                            sourceIP,
                            sourcePort
                        )
                        //						Log.d(TAG, "got last ACK after FIN, session is now closed.");
                    }
                }
                //received the last segment of data from vpn client
                if (tcpHeader.isPSH()) {
                    // Tell the NIO thread to immediately send data to the destination
                    pushDataToDestination(connection, tcpHeader)
                } else if (tcpHeader.isFIN()) {
                    //fin from vpn client is the last packet
                    //ack it
//					Log.d(TAG, "FIN from vpn client, will ack it.");
                    ackFinAck(ip4Header, tcpHeader, connection)
                } else if (tcpHeader.isRST()) {
                    resetTCPConnection(ip4Header, tcpHeader)
                }
                if (!connection.isAbortingConnection) {
                    manager.keepSessionAlive(connection)
                }
            }
        } else if (tcpHeader.isFIN()) {
            //case client sent FIN without ACK
            val connection = manager.getConnection(
                Protocol.TCP,
                destinationIP,
                destinationPort,
                sourceIP,
                sourcePort
            )
            if (connection == null) ackFinAck(
                ip4Header,
                tcpHeader,
                null
            ) else manager.keepSessionAlive(connection)
        } else if (tcpHeader.isRST()) {
            resetTCPConnection(ip4Header, tcpHeader)
        } else {
            Log.d(TAG, "unknown TCP flag")
            val str1 = getOutput(ip4Header, tcpHeader, clientPacketData.array())
            Log.d(TAG, ">>>>>>>> Received from client <<<<<<<<<<")
            Log.d(TAG, str1)
            Log.d(TAG, ">>>>>>>>>>>>>>>>>>>end receiving from client>>>>>>>>>>>>>>>>>>>>>")
        }
    }

    private fun initProxyConnect(
        clientPacketData: ByteBuffer, destinationIP: Int, destinationPort: Int,
        connection: Connection
    ) {
        if (connection.isInitConnect) {
            return
        }

        connection.isInitConnect = true
        val proxyAddress =
            getProxyAddress(clientPacketData, destinationIP, destinationPort)
        try {
            val channel = connection.channel as SocketChannel?
            val connected = channel!!.connect(proxyAddress)
            connection.isConnected = connected
            nioService.registerSession(connection)

            if (proxyAddress == manager.proxyAddress) {
                //获取进程信息
                ProcessInfoManager.instance.setConnectionOwnerUid(connection)
                Log.d(
                    TAG,
                    "Proxy Initiate connecting key:" + connection.toString() + " " + channel.localAddress + " to remote tcp server: " + channel.remoteAddress
                )
            }
        } catch (e: Exception) {
            val ips = intToIPAddress(destinationIP)
            Log.w(TAG, "Failed to reconnect to $ips:$destinationPort", e)
        }
    }

    private fun sendRstPacket(ip: IP4Header, tcp: TCPHeader, dataLength: Int) {
        val data = TCPPacketFactory.createRstData(ip, tcp, dataLength)
        writer.write(data)
        Log.d(
            TAG, "Sent RST Packet to client with dest => " +
                    intToIPAddress(ip.destinationIP) + ":" +
                    tcp.getDestinationPort()
        )
    }

    private fun sendLastAck(ip: IP4Header, tcp: TCPHeader) {
        val data = TCPPacketFactory.createResponseAckData(ip, tcp, tcp.sequenceNumber + 1)
        writer.write(data)
//		Log.d(TAG,"Sent last ACK Packet to client with dest => " +
//				PacketUtil.intToIPAddress(ip.getDestinationIP()) + ":" +
//				tcp.getDestinationPort());
    }

    private fun ackFinAck(ip: IP4Header, tcp: TCPHeader, connection: Connection?) {
        val ack = tcp.sequenceNumber + 1
        val seq = tcp.ackNumber
        val data = TCPPacketFactory.createFinAckData(ip, tcp, ack, seq, isFin = true, isAck = true)
        writer.write(data)
        if (connection != null) {
            connection.cancelKey()
            manager.closeConnection(connection)
            //			Log.d(TAG,"ACK to client's FIN and close session => "+PacketUtil.intToIPAddress(ip.getDestinationIP())+":"+tcp.getDestinationPort()
//					+"-"+PacketUtil.intToIPAddress(ip.getSourceIP())+":"+tcp.getSourcePort());
        }
    }

    private fun sendFinAck(ip: IP4Header, tcp: TCPHeader, connection: Connection) {
        val ack = tcp.sequenceNumber
        val seq = tcp.ackNumber
        val data = TCPPacketFactory.createFinAckData(ip, tcp, ack, seq, isFin = true, isAck = false)
        val stream = ByteBuffer.wrap(data)
        writer.write(data)
//        Log.d(TAG, "00000000000 FIN-ACK packet data to vpn client 000000000000")
        var vpnIp: IP4Header? = null
        try {
            vpnIp = IPPacketFactory.createIP4Header(stream)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        var vpnTcp: TCPHeader? = null
        try {
            if (vpnIp != null) vpnTcp = TCPPacketFactory.createTCPHeader(stream)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        if (vpnIp != null && vpnTcp != null) {
            val logOut = getOutput(vpnIp, vpnTcp, data)
            Log.d(TAG, logOut)
        }
//        Log.d(TAG, "0000000000000 finished sending FIN-ACK packet to vpn client 000000000000")
        connection.sendNext = seq + 1
        //avoid re-sending it, from here client should take care the rest
        connection.isClosingConnection = false
    }

    private fun pushDataToDestination(connection: Connection, tcp: TCPHeader) {
        connection.isDataForSendingReady = true
        connection.timestampReplyTo = tcp.timeStampSender
        connection.timestampSender = System.currentTimeMillis().toInt()

        // Ping the NIO thread to write this, when the session is next writable
        connection.subscribeKey(SelectionKey.OP_WRITE)
        nioService.refreshSelect(connection)
    }

    /**
     * send acknowledgment packet to VPN client
     *
     * @param acceptedDataLength Data Length
     */
    private fun sendAck(
        ipHeader: IP4Header, tcpHeader: TCPHeader, acceptedDataLength: Int, connection: Connection
    ) {
        val ackNumber = connection.recSequence + acceptedDataLength
        connection.recSequence = ackNumber
        val ackData = TCPPacketFactory.createResponseAckData(ipHeader, tcpHeader, ackNumber)
        writer.write(ackData)
    }

    /**
     * resend the last acknowledgment packet to VPN client, e.g. when an unexpected out of order
     * packet arrives.
     */
    private fun resendAck(connection: Connection) {
        val data = TCPPacketFactory.createResponseAckData(
            connection.lastIpHeader!!,
            connection.lastTcpHeader!!,
            connection.recSequence
        )
        writer.write(data)
    }

    private fun sendAckForDisorder(
        ipHeader: IP4Header, tcpHeader: TCPHeader, acceptedDataLength: Int
    ) {
        val ackNumber = tcpHeader.sequenceNumber + acceptedDataLength
        Log.e(
            TAG, "sent disorder ack, ack# " + tcpHeader.sequenceNumber +
                    " + " + acceptedDataLength + " = " + ackNumber
        )
        val data = TCPPacketFactory.createResponseAckData(ipHeader, tcpHeader, ackNumber)
        writer.write(data)
    }

    /**
     * acknowledge a packet.
     *
     * @param tcpHeader TCP Header
     */
    private fun acceptAck(tcpHeader: TCPHeader, connection: Connection) {
        val isCorrupted = isPacketCorrupted(tcpHeader)

//        connection.setPacketCorrupted(isCorrupted);
        if (isCorrupted) {
            Log.e(TAG, "prev packet was corrupted, last ack# " + tcpHeader.ackNumber)
        }
        if (tcpHeader.ackNumber > connection.sendUnAck ||
            tcpHeader.ackNumber == connection.sendNext
        ) {
//            connection.setAcked(true);
            connection.sendUnAck = tcpHeader.ackNumber
            connection.recSequence = tcpHeader.sequenceNumber
            connection.timestampReplyTo = tcpHeader.timeStampSender
            connection.timestampSender = System.currentTimeMillis().toInt()
        } else {
            Log.d(
                TAG,
                "Not Accepting ack# " + tcpHeader.ackNumber + " , it should be: " + connection.sendNext
            )
            Log.d(TAG, "Prev sendUnAck: " + connection.sendUnAck)
            //            connection.setAcked(false);
        }
    }

    /**
     * set connection as aborting so that background worker will close it.
     *
     * @param ip  IP
     * @param tcp TCP
     */
    private fun resetTCPConnection(ip: IP4Header, tcp: TCPHeader) {
        val session = manager.getConnection(
            Protocol.TCP,
            ip.destinationIP, tcp.getDestinationPort(),
            ip.sourceIP, tcp.getSourcePort()
        )
        if (session != null) {
            synchronized(session) { session.isAbortingConnection = true }
        }
    }

    /**
     * create a new client's session and SYN-ACK packet data to respond to client
     */
    @Throws(IOException::class)
    private fun replySynAck(ipHeader: IP4Header, tcpHeader: TCPHeader) {
        ipHeader.identification = 0
        val packet = TCPPacketFactory.createSynAckPacketData(ipHeader, tcpHeader)
        val tcpTransport = packet.transportHeader as TCPHeader
        val connection = manager.createTCPConnection(
            ipHeader.destinationIP, tcpHeader.getDestinationPort(),
            ipHeader.sourceIP, tcpHeader.getSourcePort()
        )
        if (connection.lastIpHeader != null) {
            // We have an existing session for this connection! We've somehow received a SYN
            // for an existing socket (or some kind of other race). We resend the last ACK
            // for this session, rejecting this SYN. Not clear why this happens, but it can.
            resendAck(connection)
            return
        }
        synchronized(connection) {
            connection.maxSegmentSize = tcpTransport.maxSegmentSize.toInt()
            connection.sendUnAck = tcpTransport.sequenceNumber
            connection.sendNext = tcpTransport.sequenceNumber + 1
            //client initial sequence has been incremented by 1 and set to ack
            connection.recSequence = tcpTransport.ackNumber
            connection.lastIpHeader = ipHeader
            connection.lastTcpHeader = tcpHeader
            if (connection.isInitConnect) {
                nioService.registerSession(connection)
            }
            writer.write(packet.buffer)
        }
    }

    private fun handleICMPPacket(clientPacketData: ByteBuffer, ipHeader: IP4Header) {
        val requestPacket = ICMPPacketFactory.parseICMPPacket(clientPacketData)
//        Log.d(TAG, "Got an ICMP ping packet, type $requestPacket")
        if (requestPacket.type == ICMPPacket.DESTINATION_UNREACHABLE_TYPE) {
            // This is a packet from the phone, telling somebody that a destination is unreachable.
            // Might be caused by issues on our end, but it's unclear what kind of issues. Regardless,
            // we can't send ICMP messages ourselves or react usefully, so we drop these silently.
            return
        } else require(requestPacket.type == ICMPPacket.ECHO_REQUEST_TYPE) {
            // We only actually support outgoing ping packets. Loudly drop anything else:
            "Unknown ICMP type (" + requestPacket.type + "). Only echo requests are supported"
        }
        pingThreadPool.execute(object : Runnable {
            override fun run() {
                try {
                    if (!isReachable(intToIPAddress(ipHeader.destinationIP))) {
                        Log.d(TAG, "Failed ping, ignoring")
                        return
                    }
                    val response = ICMPPacketFactory.buildSuccessPacket(requestPacket)

                    // Flip the address
                    val destination = ipHeader.destinationIP
                    val source = ipHeader.sourceIP
                    ipHeader.sourceIP = destination
                    ipHeader.destinationIP = source
                    val responseData = ICMPPacketFactory.packetToBuffer(ipHeader, response)
                    Log.d(TAG, "Successful ping response")
                    writer.write(responseData)
                } catch (e: Exception) {
                    Log.w(TAG, "Handling ICMP failed with " + e.message)
                    return
                }
            }

            private fun isReachable(ipAddress: String): Boolean {
                return try {
                    InetAddress.getByName(ipAddress).isReachable(10000)
                } catch (_: IOException) {
                    false
                }
            }
        })
    }
}