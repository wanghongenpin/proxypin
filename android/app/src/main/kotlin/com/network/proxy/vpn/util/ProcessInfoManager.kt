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

    private val localPortCache =
        SimpleCache<Int, NetworkInfo>(10_000, 60, TimeUnit.SECONDS)


    private val appInfoCache = SimpleCache<Int, ProcessInfo>(10_000, 300, TimeUnit.SECONDS)


    var activity: Context? = null

    @RequiresApi(Build.VERSION_CODES.N)
    fun setConnectionOwnerUid(connection: Connection) {
        CoroutineScope(Dispatchers.IO).launch {

            val sourceAddress =
                InetSocketAddress(PacketUtil.intToIPAddress(connection.sourceIp), connection.sourcePort)
            val destinationAddress = InetSocketAddress(
                PacketUtil.intToIPAddress(connection.destinationIp), connection.destinationPort
            )

            val uid = getProcessInfoUid(sourceAddress, destinationAddress)
            val channel = connection.channel
            if (uid != null && uid != Process.INVALID_UID && channel is SocketChannel && channel.isOpen) {
                val localAddress = channel.localAddress as InetSocketAddress
                val networkInfo =
                    NetworkInfo(uid, destinationAddress.hostString, destinationAddress.port)
                localPortCache.put(localAddress.port, networkInfo)
            }
        }
    }

    fun removeConnection(connection: Connection) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return
        }

        val channel = connection.channel
        if (channel is SocketChannel && channel.isOpen) {
            val localAddress = channel.localAddress as InetSocketAddress
            localPortCache.remove(localAddress.port)
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