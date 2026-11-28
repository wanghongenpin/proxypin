package com.network.proxy.root

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface

/**
 * 网卡枚举与类型识别（原始抓包选择网卡、Root 模式按网卡捕获共用）。
 *
 * 类型优先取自 ConnectivityManager（系统当前网络，准确），其余按名称推断：
 * 热点 / USB / 蓝牙共享网卡不在系统网络列表中，按常见命名识别。
 */
object NetInterfaces {
    private const val TAG = "NetInterfaces"

    const val WIFI = "wifi"
    const val CELLULAR = "cellular"
    const val ETHERNET = "ethernet"
    const val VPN = "vpn"
    const val TETHER = "tether"
    const val LOOPBACK = "loopback"
    const val OTHER = "other"

    /** 热点 / USB / 蓝牙共享网卡的常见命名（iptables `+` 为前缀通配） */
    val TETHER_PATTERNS = listOf("ap+", "swlan+", "softap+", "wlan1", "wlan2", "rndis+", "ncm+", "usb+", "bt-pan+", "wigig+")

    data class Info(
        val name: String,
        val type: String,
        val up: Boolean,
        val addresses: List<String>,
        /** 系统当前默认网络 */
        val isDefault: Boolean
    ) {
        fun toMap(): Map<String, Any> =
            mapOf("name" to name, "type" to type, "up" to up, "addresses" to addresses, "isDefault" to isDefault)
    }

    fun list(context: Context): List<Info> {
        val systemTypes = HashMap<String, String>()
        var defaultIface: String? = null
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val active = cm.activeNetwork
            @Suppress("DEPRECATION")
            for (network in cm.allNetworks) {
                val iface = cm.getLinkProperties(network)?.interfaceName ?: continue
                val caps = cm.getNetworkCapabilities(network) ?: continue
                systemTypes[iface] = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> VPN
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> WIFI
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> CELLULAR
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> ETHERNET
                    else -> OTHER
                }
                if (network == active && !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) defaultIface = iface
            }
        } catch (e: Exception) {
            Log.w(TAG, "connectivity query failed", e)
        }

        val javaIfaces = HashMap<String, NetworkInterface>()
        try {
            NetworkInterface.getNetworkInterfaces()?.toList()?.forEach { javaIfaces[it.name] = it }
        } catch (e: Exception) {
            Log.w(TAG, "NetworkInterface enumeration failed", e)
        }

        val names = LinkedHashSet<String>()
        names += javaIfaces.keys
        // 不走 su：抓包期间 root shell 被连接反查频繁占用，排队会导致列表半天出不来；
        // 未连接的网卡对抓包没有意义，Java API 看不到也无妨（结果也不再因是否开过抓包而不同）
        File("/sys/class/net").list()?.let { names += it }
        names.removeAll { it.isBlank() }

        return names.map { name ->
            val nif = javaIfaces[name]
            val addresses = nif?.inetAddresses?.toList().orEmpty()
                .sortedBy { if (it is Inet4Address) 0 else 1 }
                .mapNotNull { it.hostAddress?.substringBefore('%') }
            val up = try {
                nif?.isUp ?: (File("/sys/class/net/$name/operstate").readText().trim() == "up")
            } catch (e: Exception) {
                false
            }
            val type = systemTypes[name] ?: guessType(name, nif)
            Info(name, type, up, addresses, name == defaultIface)
        }.sortedWith(compareBy<Info>({ !it.isDefault }, { !(it.up && it.addresses.isNotEmpty()) }, { typeOrder(it.type) }, { it.name }))
    }

    /** 当前处于共享（热点 / USB / 蓝牙）状态的网卡名 */
    fun tetherInterfaces(context: Context): List<String> =
        list(context).filter { it.type == TETHER && it.up }.map { it.name }

    private fun guessType(name: String, nif: NetworkInterface?): String {
        if (name == "lo" || nif?.isLoopback == true) return LOOPBACK
        if (name.startsWith("tun") || name.startsWith("ppp") || name.startsWith("ipsec")) return VPN
        if (Regex("^(ap|swlan|softap|rndis|ncm|usb|bt-pan|wigig)\\d*").containsMatchIn(name)) return TETHER
        // 非系统网络但有 IPv4 地址的 wlan（如 wlan1 / STA 关闭时的 wlan0 热点）
        if (name.startsWith("wlan")) {
            val hasV4 = nif?.inetAddresses?.toList().orEmpty().any { it is Inet4Address }
            return if (hasV4) TETHER else WIFI
        }
        if (name.startsWith("rmnet") || name.startsWith("ccmni") || name.startsWith("seth") || name.startsWith("v4-")) return CELLULAR
        if (name.startsWith("eth")) return ETHERNET
        return OTHER
    }

    private fun typeOrder(type: String) = when (type) {
        WIFI -> 0
        CELLULAR -> 1
        ETHERNET -> 2
        TETHER -> 3
        VPN -> 4
        OTHER -> 5
        else -> 6
    }
}
