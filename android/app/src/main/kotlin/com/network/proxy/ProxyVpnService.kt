package com.network.proxy

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.IpPrefix
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import com.network.proxy.plugin.VpnServicePlugin.Companion.REQUEST_CODE
import com.network.proxy.vpn.ConnectionManager
import com.network.proxy.vpn.ProxyVpnThread
import com.network.proxy.vpn.socket.ProtectSocket
import com.network.proxy.vpn.socket.ProtectSocketHolder
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface

/**
 * VPN服务
 * @author wanghongen
 */
class ProxyVpnService : VpnService(), ProtectSocket {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: ProxyVpnThread? = null

    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    @Volatile
    private var activeNetwork: Network? = null

    /**
     * 代理是否在本机。启动时根据 proxyHost 是否为本机网卡地址判定。
     * 仅本机代理在切网时需要把转发地址刷新为新网络的本地 IP；远程代理地址不变。见 issue #864。
     */
    @Volatile
    private var localProxy: Boolean = false

    companion object {
        const val MAX_PACKET_LEN = 1500

        const val VIRTUAL_HOST = "10.0.0.2"

        const val PROXY_HOST_KEY = "ProxyHost"
        const val PROXY_PORT_KEY = "ProxyPort"
        const val ALLOW_APPS_KEY = "AllowApps" //允许的名单
        const val DISALLOW_APPS_KEY = "DisallowApps" //禁止的名单
        const val SET_SYSTEM_PROXY_KEY = "SetSystemProxy"
        const val PROXY_PASS_DOMAINS_KEY = "ProxyPassDomains"

        /**
         * 动作：断开连接
         */
        const val ACTION_DISCONNECT = "DISCONNECT"

        /**
         * 通知配置
         */
        private const val NOTIFICATION_ID = 9527
        const val VPN_NOTIFICATION_CHANNEL_ID = "vpn-notifications"

        var isRunning = false

        var host: String? = null
        var port: Int = 9099
        var allowApps: ArrayList<String>? = null
        var disallowApps: ArrayList<String>? = null
        var setSystemProxy: Boolean = true

        var proxyPassDomains: ArrayList<String>? = null

        fun stopVpnIntent(context: Context): Intent {
            return Intent(context, ProxyVpnService::class.java).also {
                it.action = ACTION_DISCONNECT
            }
        }

        fun startVpnIntent(
            context: Context,
            proxyHost: String? = host,
            proxyPort: Int? = port,
            allowApps: ArrayList<String>? = this.allowApps,
            disallowApps: ArrayList<String>? = this.disallowApps,
            setSystemProxy: Boolean = true,
            proxyPassDomains: ArrayList<String>? = null
        ): Intent {
            return Intent(context, ProxyVpnService::class.java).also {
                it.putExtra(PROXY_HOST_KEY, proxyHost)
                it.putExtra(PROXY_PORT_KEY, proxyPort)
                it.putStringArrayListExtra(ALLOW_APPS_KEY, allowApps)
                it.putStringArrayListExtra(DISALLOW_APPS_KEY, disallowApps)
                it.putExtra(SET_SYSTEM_PROXY_KEY, setSystemProxy)
                it.putStringArrayListExtra(PROXY_PASS_DOMAINS_KEY, proxyPassDomains)
            }
        }

        /**
         * 准备vpn<br>
         * 设备可能弹出连接vpn提示
         */
        fun prepareVpn(
            activity: Activity,
            host: String,
            port: Int,
            allowApps: ArrayList<String>?,
            disallowApps: ArrayList<String>?,
            setSystemProxy: Boolean = true,
            proxyPassDomains: ArrayList<String>? = null
        ): Boolean {
            val intent = prepare(activity)
            if (intent != null) {
                ProxyVpnService.host = host
                ProxyVpnService.port = port
                ProxyVpnService.allowApps = allowApps
                ProxyVpnService.disallowApps = disallowApps
                ProxyVpnService.setSystemProxy = setSystemProxy
                ProxyVpnService.proxyPassDomains = proxyPassDomains

                activity.startActivityForResult(intent, REQUEST_CODE)
                return false
            }
            return true
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        disconnect()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            return START_NOT_STICKY
        }

        return if (intent.action == ACTION_DISCONNECT) {
            disconnect()
            START_NOT_STICKY
        } else {
            val proxyHost = intent.getStringExtra(PROXY_HOST_KEY) ?: (host ?: "127.0.0.1")
            val proxyPort = intent.getIntExtra(PROXY_PORT_KEY, port)
            val allowPackages =
                intent.getStringArrayListExtra(ALLOW_APPS_KEY) ?: allowApps ?: ArrayList()
            val disallowPackages =
                intent.getStringArrayListExtra(DISALLOW_APPS_KEY) ?: disallowApps ?: ArrayList()
            val setSystemProxy = intent.getBooleanExtra(SET_SYSTEM_PROXY_KEY, setSystemProxy)
            val proxyPassDomains = intent.getStringArrayListExtra(PROXY_PASS_DOMAINS_KEY)

            connect(
                proxyHost,
                proxyPort,
                allowPackages,
                disallowPackages,
                setSystemProxy,
                proxyPassDomains
            )
            START_STICKY
        }
    }

    private fun disconnect() {
        unregisterNetworkCallback()
        vpnThread?.run { stopThread() }
        vpnInterface?.close()
        stopForeground(STOP_FOREGROUND_REMOVE)
        vpnInterface = null
        isRunning = false
    }

    private fun connect(
        proxyHost: String,
        proxyPort: Int,
        allowPackages: ArrayList<String>?,
        disallowPackages: ArrayList<String>?,
        setSystemProxy: Boolean = true,
        proxyPassDomains: ArrayList<String>? = null
    ) {
        localProxy = isLocalProxyHost(proxyHost)
        Log.i(
            "ProxyVpnService",
            "startVpn $proxyHost:$proxyPort systemProxy: $setSystemProxy localProxy: $localProxy allowPackages: $allowPackages proxyPassDomains: $proxyPassDomains"
        )

        host = proxyHost
        port = proxyPort
        allowApps = allowPackages
        disallowApps = disallowPackages
        ProxyVpnService.proxyPassDomains = proxyPassDomains
        vpnInterface = createVpnInterface(
            proxyHost,
            proxyPort,
            allowPackages,
            disallowPackages,
            setSystemProxy,
            proxyPassDomains
        )
        if (vpnInterface == null) {
            val alertDialog = Intent(applicationContext, VpnAlertDialog::class.java)
                .setAction("com.network.proxy.ProxyVpnService")
            alertDialog.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(alertDialog)
            return
        }

        ProtectSocketHolder.setProtectSocket(this)
        showServiceNotification()
        vpnThread = ProxyVpnThread(
            vpnInterface!!,
            proxyHost,
            proxyPort,
            proxyPassDomains
        )
        vpnThread!!.start()
        registerNetworkCallback()
        isRunning = true
    }

    /**
     * 监听默认网络变化（WiFi <-> 移动数据）。见 issue #864。
     *
     * 网络切换后：
     *  1. 调用 [setUnderlyingNetworks] 把 VPN 底层网络更新为当前网络（VPN 标准做法，避免 Android
     *     把底层网络钉死在建立时的网络上；直连的 UDP / proxyPassDomains 绕过套接字仍走物理网络，需要它）。
     *  2. 本机代理模式下，把转发地址刷新为新网络的本地 IP（旧网络的本地 IP 已随网络失效）。
     *  3. 关闭旧连接，让切网瞬间残留的在途请求立即在新网络上重建。
     */
    private fun registerNetworkCallback() {
        if (networkCallback != null) return // 幂等：避免重复注册导致回调泄漏
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        connectivityManager = cm
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                onDefaultNetworkChanged(network)
            }
            // 不覆写 onLost：清空 activeNetwork 会在 break-before-make（先 onLost 再 onAvailable）
            // 的回调顺序下把 previous 置 null，导致该次切网被误判为首次注册而跳过重置。
        }
        networkCallback = callback
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                cm.registerDefaultNetworkCallback(callback)
            } else {
                val request = NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build()
                cm.registerNetworkCallback(request, callback)
            }
        } catch (e: Exception) {
            Log.w("ProxyVpnService", "registerNetworkCallback failed", e)
            networkCallback = null
        }
    }

    private fun onDefaultNetworkChanged(network: Network) {
        val previous = activeNetwork
        activeNetwork = network

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            try {
                setUnderlyingNetworks(arrayOf(network))
            } catch (e: Exception) {
                Log.w("ProxyVpnService", "setUnderlyingNetworks failed", e)
            }
        }

        // 首次注册回调 previous 为 null；同一网络重复回调也跳过。仅真正切换网络时重置连接。
        if (previous == null || previous == network) return

        Log.i("ProxyVpnService", "default network changed, reset connections (issue #864)")

        // 本机代理：转发地址绑定的是旧网络的本地 IP，切网后失效，需刷新为新网络的本地 IP。
        // 远程代理：地址在其它设备，不随本机网络变化，跳过。
        if (localProxy) {
            val newIp = getNetworkIpv4(network)
            if (newIp != null) {
                ConnectionManager.instance.proxyAddress = InetSocketAddress(newIp, port)
                Log.i("ProxyVpnService", "proxyAddress updated to $newIp:$port")
            } else {
                Log.w("ProxyVpnService", "no IPv4 on new network, keep old proxyAddress")
            }
        }

        // 关闭旧连接，使其在新网络/新转发地址上重建。
        ConnectionManager.instance.closeAll()
    }

    /**
     * 获取指定网络的本机 IPv4 地址（排除回环/通配地址）。
     */
    private fun getNetworkIpv4(network: Network): String? {
        return try {
            val lp = connectivityManager?.getLinkProperties(network) ?: return null
            lp.linkAddresses
                .map { it.address }
                .firstOrNull { it is Inet4Address && !it.isLoopbackAddress && !it.isAnyLocalAddress }
                ?.hostAddress
        } catch (e: Exception) {
            Log.w("ProxyVpnService", "getNetworkIpv4 failed", e)
            null
        }
    }

    /**
     * 判断 proxyHost 是否指向本机（本机网卡地址或回环）。启动时调用，用于区分本机/远程代理。
     */
    private fun isLocalProxyHost(proxyHost: String): Boolean {
        return try {
            val target = InetAddress.getByName(proxyHost)
            if (target.isLoopbackAddress || target.isAnyLocalAddress) return true
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty().any { nif ->
                nif.inetAddresses.toList().any { it == target }
            }
        } catch (e: Exception) {
            Log.w("ProxyVpnService", "isLocalProxyHost failed for $proxyHost", e)
            false
        }
    }

    private fun unregisterNetworkCallback() {
        val callback = networkCallback ?: return
        try {
            connectivityManager?.unregisterNetworkCallback(callback)
        } catch (e: Exception) {
            Log.w("ProxyVpnService", "unregisterNetworkCallback failed", e)
        }
        networkCallback = null
        activeNetwork = null
    }

    private fun showServiceNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val notificationChannel = NotificationChannel(
                VPN_NOTIFICATION_CHANNEL_ID,
                "VPN Status",
                NotificationManager.IMPORTANCE_LOW
            )
            notificationManager.createNotificationChannel(notificationChannel)
        }

        val pendingActivityIntent: PendingIntent =
            Intent(this, MainActivity::class.java).let { notificationIntent ->
                PendingIntent.getActivity(this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE)
            }

        val notification: Notification =
            NotificationCompat.Builder(this, VPN_NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(pendingActivityIntent)
                .setContentTitle(getString(R.string.vpn_active_notification_title))
                .setContentText(getString(R.string.vpn_active_notification_content))
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification)
        }
    }


    private fun createVpnInterface(
        proxyHost: String,
        proxyPort: Int,
        allowPackages: List<String>?,
        disallowApps: ArrayList<String>?,
        setSystemProxy: Boolean = true,
        proxyPassDomains: ArrayList<String>? = null
    ):
            ParcelFileDescriptor? {
        val build = Builder()
            .setMtu(MAX_PACKET_LEN)
            .addAddress(VIRTUAL_HOST, 32)
            .addRoute("0.0.0.0", 0)
            .setSession(baseContext.applicationInfo.name)
            .setBlocking(true)

        // 处理 proxyPassDomains 中的 CIDR 格式，添加到 excludeRoute
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && proxyPassDomains != null) {
            applyExcludeRoutes(build, proxyPassDomains)
        }

        val packages = allowPackages?.filter { it != baseContext.packageName }
        if (packages?.isNotEmpty() == true) {
            packages.forEach {
                build.addAllowedApplication(it)
            }
        } else {
            build.addDisallowedApplication(baseContext.packageName)
        }

        disallowApps?.forEach {
            if (packages?.contains(it) == true) return@forEach
            build.addDisallowedApplication(it)
        }

        build.setConfigureIntent(
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE
            )
        )

        return build.apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setMetered(false)
            }

            if (setSystemProxy && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Log.d("ProxyVpnService", "set system proxy $proxyHost:$proxyPort")
                val buildProxy = ProxyInfo.buildDirectProxy(proxyHost, proxyPort)
                setHttpProxy(buildProxy)
            }
        }.establish()
    }

    /**
     * 应用排除路由规则
     * 根据 proxyPassDomains 列表配置 VPN 的 excludeRoute
     *
     * @param builder VPN Builder 实例
     * @param proxyPassDomains 需要排除的域名/IP列表
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun applyExcludeRoutes(builder: Builder, proxyPassDomains: ArrayList<String>) {

        proxyPassDomains.forEach { domain ->
            try {
                val trimmedDomain = domain.trim()
                when {
                    // 2. localhost 或 127.0.0.1
                    trimmedDomain == "localhost" || trimmedDomain == "127.0.0.1" -> {
                        Log.d("ProxyVpnService", "Skipped excludeRoute for localhost: $trimmedDomain")
                    }

                    // 1. CIDR 格式：192.168.0.0/16
                    trimmedDomain.contains("/") -> {
                        addCidrExcludeRoute(builder, trimmedDomain)
                    }

                    // 3. 单个 IP 地址（不含通配符）
                    !trimmedDomain.contains("*") && isValidIpAddress(trimmedDomain) -> {
                        addSingleIpExcludeRoute(builder, trimmedDomain)
                    }
                    // 4. 域名和通配符域名会被跳过（不能用于 excludeRoute）
                }
            } catch (e: Exception) {
                Log.w("ProxyVpnService", "Error processing proxyPassDomain: $domain", e)
            }
        }
    }

    /**
     * 添加 CIDR 格式的排除路由
     * @param builder VPN Builder 实例
     * @param cidr CIDR 格式的地址，如 "192.168.0.0/16"
     */
    private fun addCidrExcludeRoute(builder: Builder, cidr: String) {
        try {
            val parts = cidr.split("/")
            if (parts.size != 2) {
                Log.w("ProxyVpnService", "Invalid CIDR format: $cidr")
                return
            }

            val ipAddress = parts[0]
            val prefixLength = parts[1].toIntOrNull()

            if (prefixLength == null || prefixLength !in 0..32) {
                Log.w("ProxyVpnService", "Invalid prefix length in CIDR: $cidr")
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inetAddress = InetAddress.getByName(ipAddress)
                builder.excludeRoute(IpPrefix(inetAddress, prefixLength))
                Log.d("ProxyVpnService", "Added excludeRoute: $cidr")
            }
        } catch (e: Exception) {
            Log.w("ProxyVpnService", "Failed to add CIDR excludeRoute: $cidr", e)
        }
    }

    /**
     * 添加单个 IP 地址的排除路由
     * @param builder VPN Builder 实例
     * @param ipAddress IP 地址字符串
     */
    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun addSingleIpExcludeRoute(builder: Builder, ipAddress: String) {
        val inetAddress = InetAddress.getByName(ipAddress)
        builder.excludeRoute(IpPrefix(inetAddress, 32))
        Log.d("ProxyVpnService", "Added excludeRoute for single IP: $ipAddress/32")
    }

    /**
     * 检查字符串是否是有效的 IPv4 地址格式
     * @param ip IP 地址字符串
     * @return 是否是有效的 IPv4 地址
     */
    private fun isValidIpAddress(ip: String): Boolean {
        return ip.matches(Regex("\\d+\\.\\d+\\.\\d+\\.\\d+"))
    }


}
