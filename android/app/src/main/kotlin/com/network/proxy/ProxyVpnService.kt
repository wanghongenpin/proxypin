package com.network.proxy

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.IpPrefix
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import com.network.proxy.plugin.VpnServicePlugin.Companion.REQUEST_CODE
import com.network.proxy.vpn.ProxyVpnThread
import com.network.proxy.vpn.socket.ProtectSocket
import com.network.proxy.vpn.socket.ProtectSocketHolder
import java.net.InetAddress

/**
 * VPN服务
 * @author wanghongen
 */
class ProxyVpnService : VpnService(), ProtectSocket {
    private var vpnInterface: ParcelFileDescriptor? = null
    private var vpnThread: ProxyVpnThread? = null

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
        Log.i(
            "ProxyVpnService",
            "startVpn $proxyHost:$proxyPort systemProxy: $setSystemProxy allowPackages: $allowPackages proxyPassDomains: $proxyPassDomains"
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
        isRunning = true
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
