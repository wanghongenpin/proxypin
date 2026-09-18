package com.network.proxy.vpn.util

import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.system.OsConstants
import android.util.Log
import androidx.annotation.RequiresApi
import com.network.proxy.ProxyVpnService
import com.network.proxy.plugin.ProcessInfo
import com.network.proxy.vpn.Connection
import kotlinx.coroutines.CoroutineScope
import java.io.File
import java.net.InetSocketAddress
import java.nio.channels.SocketChannel
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 进程信息管理器，用于获取进程信息
 * @author wanghongen
 */
class ProcessInfoManager private constructor() {
    companion object {
        @Suppress("all")
        val instance = ProcessInfoManager()
    }

    class NetworkInfo(val uid: Int, val remoteHost: String, val remotePort: Int)

    class RemoteAddress(val host: String, val port: Int)

    private val localPortCache =
        SimpleCache<Int, NetworkInfo>(10_000, 60, TimeUnit.SECONDS)

    // 连接的真实目的地址，key 为 VPN→本地代理 socket 的 local port，
    // 与代理侧 accepted socket 的 remoteSocketAddress.port 一致。
    // 必须在数据转发给本地代理前同步写入：明文 HTTP 的 Host 头可能不含端口，
    // 端口纠正不能依赖异步的 uid 查询先完成，否则会偶发拨到默认 80 端口(#530)。
    private val remoteAddressCache =
        SimpleCache<Int, RemoteAddress>(10_000, 60, TimeUnit.SECONDS)


    private val appInfoCache = SimpleCache<Int, ProcessInfo>(10_000, 300, TimeUnit.SECONDS)


    var activity: Context? = null

    @RequiresApi(Build.VERSION_CODES.N)
    fun setConnectionOwnerUid(connection: Connection) {
        val localPort = recordRemoteAddress(connection)

        CoroutineScope(Dispatchers.IO).launch {
            // connect 尚未完成时同步阶段可能取不到 local port，这里连接已就绪，补记一次。
            val port = localPort ?: recordRemoteAddress(connection)

            val sourceAddress =
                InetSocketAddress(PacketUtil.intToIPAddress(connection.sourceIp), connection.sourcePort)
            val destinationAddress = InetSocketAddress(
                PacketUtil.intToIPAddress(connection.destinationIp), connection.destinationPort
            )

            val uid = getProcessInfoUid(sourceAddress, destinationAddress)
            if (uid != null && uid != Process.INVALID_UID && port != null) {
                val networkInfo =
                    NetworkInfo(uid, destinationAddress.hostString, destinationAddress.port)
                localPortCache.put(port, networkInfo)
            }
        }
    }

    /**
     * 同步记录连接的真实目的地址，返回 VPN→本地代理 socket 的 local port；
     * 拿不到本地端口时返回 null(不影响后续异步 uid 查询)。
     */
    private fun recordRemoteAddress(connection: Connection): Int? {
        val channel = connection.channel
        if (channel !is SocketChannel || !channel.isOpen) {
            return null
        }
        return try {
            val localPort = (channel.localAddress as InetSocketAddress).port
            val destinationHost = PacketUtil.intToIPAddress(connection.destinationIp)
            remoteAddressCache.put(localPort, RemoteAddress(destinationHost, connection.destinationPort))
            localPort
        } catch (e: Exception) {
            Log.w("ProcessInfoManager", "recordRemoteAddress", e)
            null
        }
    }

    fun removeConnection(connection: Connection) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return
        }

        val channel = connection.channel
        if (channel is SocketChannel && channel.isOpen) {
            try {
                val localAddress = channel.localAddress as InetSocketAddress
                localPortCache.remove(localAddress.port)
                remoteAddressCache.remove(localAddress.port)
            } catch (e: java.nio.channels.ClosedChannelException) {
                Log.w("ProcessInfoManager", "removeConnection", e)
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun getProcessInfoUid(
        localAddress: InetSocketAddress, remoteAddress: InetSocketAddress
    ): Int? {
//        Log.d(TAG, "getProcessInfo: $localAddress $remoteAddress")

        if (activity == null) {
            return null
        }

        try {
            val connectivityManager: ConnectivityManager =
                activity!!.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

            val uid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                connectivityManager.getConnectionOwnerUid(
                    OsConstants.IPPROTO_TCP, localAddress, remoteAddress
                )
            } else {
                val method = ConnectivityManager::class.java.getMethod(
                    "getConnectionOwnerUid",
                    Int::class.javaPrimitiveType,
                    InetSocketAddress::class.java,
                    InetSocketAddress::class.java
                )
                method.invoke(
                    connectivityManager, OsConstants.IPPROTO_TCP, localAddress, remoteAddress
                ) as Int
            }

            if (uid != Process.INVALID_UID) {
                return uid
            }
        } catch (e: Exception) {
            Log.w("ProcessInfoManager", "Exception in getProcessInfoUid", e)
            return null
        }

        Log.w(
            "ProcessInfoManager",
            "Failed to get UID for local address $localAddress and remote address $remoteAddress"
        )
        return null
    }

    suspend fun getProcessInfoByPort(host: String?, localPort: Int): ProcessInfo? {
        val networkInfo = localPortCache.get(localPort)
        if (networkInfo != null) {
            val processInfo = getProcessInfo(networkInfo.uid)
            if (processInfo != null) {
                val result = processInfo.copy()
                result["remoteHost"] = networkInfo.remoteHost
                result["remotePort"] = networkInfo.remotePort
                return result
            }
            return null
        }

        if (host == null || localPort <= 0 || ProxyVpnService.host == null || ProxyVpnService.port <= 0) {
            Log.w("ProcessInfoManager", "Invalid host or local port: $host:$localPort or ProxyVpnService not initialized")
            return null
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            return withContext(Dispatchers.IO) {
                val localAddress = InetSocketAddress(host, localPort)
                val remoteAddress = InetSocketAddress(ProxyVpnService.host, ProxyVpnService.port)

                val uid = getProcessInfoUid(localAddress, remoteAddress)

                if (uid == null || uid == Process.INVALID_UID) {
                    return@withContext null
                }


                val processInfo = getProcessInfo(uid)
                if (processInfo != null) {
                    localPortCache.put(
                        localPort, NetworkInfo(uid, remoteAddress.hostString, remoteAddress.port)
                    )

                    val result = processInfo.copy()
                    result["remoteHost"] = remoteAddress.hostString
                    result["remotePort"] = remoteAddress.port
                    return@withContext result
                } else {
                    Log.w("ProcessInfoManager", "No process info found for UID: $uid")
                    null
                }
            }
        } else {
            Log.w("ProcessInfoManager", "Access to /proc/net/tcp is restricted on non-rooted devices.")
        }
        return null
    }

    fun getRemoteAddressByPort(localPort: Int): Map<String, Any>? {
        // 优先返回同步记录的真实目的地址；localPortCache 里的地址可能来自
        // getProcessInfoByPort 的回退写入(其 remoteAddress 是本地代理自身)。
        remoteAddressCache.get(localPort)?.let { address ->
            return mapOf(
                "remoteHost" to address.host,
                "remotePort" to address.port
            )
        }

        val networkInfo = localPortCache.get(localPort)
        if (networkInfo != null) {
            return mapOf(
                "remoteHost" to networkInfo.remoteHost,
                "remotePort" to networkInfo.remotePort
            )
        }
        return null
    }

    private fun getProcessInfo(uid: Int): ProcessInfo? {
        var appInfo = appInfoCache.get(uid)
        if (appInfo != null) return appInfo

        val packageManager = activity?.packageManager ?: return null
        val pkgNames: Array<String>? = try {
            packageManager.getPackagesForUid(uid)
        } catch (e: Exception) {
            Log.w("ProcessInfoManager", "getPackagesForUid SecurityException: $uid", e)
            null
        }
        if (pkgNames == null) return null

        for (pkgName in pkgNames) {
            try {
                val applicationInfo = packageManager.getApplicationInfo(pkgName, 0)
                appInfo = ProcessInfo.create(packageManager, applicationInfo)
                appInfoCache.put(uid, appInfo)
                return appInfo
            } catch (e: Exception) {
                // Ignore packages that can't be found
            }
        }
        return null
    }

}
