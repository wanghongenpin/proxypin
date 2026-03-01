package com.network.proxy.vpn

import android.os.Build
import android.util.Log
import com.network.proxy.vpn.socket.CloseableConnection
import com.network.proxy.vpn.socket.Constant
import com.network.proxy.vpn.socket.ProtectSocketHolder.Companion.protect
import com.network.proxy.vpn.util.PacketUtil
import com.network.proxy.vpn.util.ProcessInfoManager
import java.io.IOException
import java.net.InetSocketAddress
import java.net.SocketAddress
import java.nio.ByteBuffer
import java.nio.channels.DatagramChannel
import java.nio.channels.SocketChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentMap

/**
 * 管理VPN客户端的连接
 */
class ConnectionManager private constructor() : CloseableConnection {
    //单例
    companion object {
        private const val TAG = "ConnectionManager"
        val instance = ConnectionManager()
    }

    private val table: ConcurrentMap<String, Connection> = ConcurrentHashMap()
    var proxyAddress: InetSocketAddress? = null
    var proxyPassDomains: ArrayList<String>? = null

    private val DEFAULT_PORTS: List<Int> = listOf(
        80,  // HTTP
        443,  // HTTPS
        8080,  // Common local dev ports
        8000, 8080, 8888, 9000 // Common local dev ports
    )

    override fun closeConnection(connection: Connection) {
        closeConnection(
            connection.protocol, connection.destinationIp, connection.destinationPort,
            connection.sourceIp, connection.sourcePort
        )
    }

    /**
     * 从内存中删除连接，然后关闭套接字。
     *
     */
    fun closeConnection(protocol: Protocol, ip: Int, port: Int, srcIp: Int, srcPort: Int) {
        val key = Connection.getConnectionKey(protocol, ip, port, srcIp, srcPort)
        val connection: Connection? = table.remove(key)
        Log.d(TAG, "close connection $key")

        connection?.let {
            val channel = connection.channel
            try {
                channel?.close()
            } catch (e: IOException) {
                e.printStackTrace()
            }
        }
    }

    fun getConnection(
        protocol: Protocol, ip: Int, port: Int, srcIp: Int, srcPort: Int
    ): Connection? {
        val key = Connection.getConnectionKey(protocol, ip, port, srcIp, srcPort)
        return getConnectionByKey(key)
    }

    fun getConnectionByKey(key: String?): Connection? {
        return table[key]
    }

    /**
     * 创建tcp连接
     */
    fun createTCPConnection(ip: Int, port: Int, srcIp: Int, srcPort: Int): Connection {
        val key = Connection.getConnectionKey(Protocol.TCP, ip, port, srcIp, srcPort)
        val existingConnection: Connection? = table[key]
        if (existingConnection != null) {
            return existingConnection
        }

        val connection = Connection(Protocol.TCP, srcIp, srcPort, ip, port, this)

        val channel: SocketChannel = SocketChannel.open()
        channel.socket().keepAlive = true
        channel.socket().tcpNoDelay = true
        channel.socket().soTimeout = 0
        channel.socket().receiveBufferSize = Constant.MAX_RECEIVE_BUFFER_SIZE
        channel.configureBlocking(false)

        Log.d(TAG, "created new SocketChannel for $key")

        protect(channel.socket())

        connection.channel = channel

        var socketAddress: SocketAddress? = null
//        if (DEFAULT_PORTS.contains(port)) {
//            socketAddress = proxyAddress
//        }

        connection.isInitConnect = socketAddress != null

        if (socketAddress != null) {
            val connected = channel.connect(socketAddress)
            connection.isConnected = connected
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                //获取进程信息
                ProcessInfoManager.instance.setConnectionOwnerUid(connection)
                Log.d(
                    TAG,
                    "Initiate connecting  " + channel.localAddress + " to remote tcp server: " + channel.remoteAddress
                )
            }
        }

        table[key] = connection
        return connection
    }


    @Throws(IOException::class)
    fun createUDPConnection(ip: Int, port: Int, srcIp: Int, srcPort: Int): Connection {
        val keys = Connection.getConnectionKey(Protocol.UDP, ip, port, srcIp, srcPort)

        val existingConnection: Connection? = table[keys]
        if (existingConnection != null) return existingConnection

        val connection = Connection(Protocol.UDP, srcIp, srcPort, ip, port, this)
        val channel: DatagramChannel = DatagramChannel.open()
        channel.socket().soTimeout = 0
        channel.configureBlocking(false)
        protect(channel.socket())
        connection.channel = channel

        // Initiate connection early to reduce latency
        val ips = PacketUtil.intToIPAddress(ip)
        val socketAddress: SocketAddress = InetSocketAddress(ips, port)
        channel.connect(socketAddress)
        connection.isConnected = channel.isConnected
        table[keys] = connection

        return connection
    }

    /**
     * 添加来自客户端的数据，该数据稍后将在接收到PSH标志时发送到目的服务器。
     */
    fun addClientData(buffer: ByteBuffer, session: Connection): Int {
        return if (buffer.limit() <= buffer.position()) 0 else session.setSendingData(buffer)
    }

    /**
     * 阻止java垃圾收集器收集会话
     */
    fun keepSessionAlive(connection: Connection) {
        val key = Connection.getConnectionKey(
            connection.protocol, connection.destinationIp, connection.destinationPort,
            connection.sourceIp, connection.sourcePort
        )
        table[key] = connection
    }
}