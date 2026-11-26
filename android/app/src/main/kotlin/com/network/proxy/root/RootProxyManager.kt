package com.network.proxy.root

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.util.Log
import com.network.proxy.vpn.util.SimpleCache
import java.net.InetAddress
import java.util.concurrent.TimeUnit

/**
 * Root 透明代理：通过 iptables nat 表把指定应用/端口的 TCP 流量重定向到 ProxyPin 代理端口，
 * 不占用系统 VPN 通道（可与其它 VPN 应用共存）。
 *
 * 规则全部放在独立的 PROXYPIN_* 链中，启动前先清理，停止时整体删除，避免残留。
 *
 * 原始目的地址/应用归属通过 [TcpConnectionTable] 反查，供 Dart 侧
 * getRemoteAddressByPort / getProcessByPort 使用（与 VPN 模式接口一致）。
 */
class RootProxyManager private constructor() {
    companion object {
        private const val TAG = "RootProxyManager"
        val instance = RootProxyManager()

        const val NAT_CHAIN = "PROXYPIN_OUT"
        const val FILTER6_CHAIN = "PROXYPIN_OUT6"
        const val QUIC_CHAIN = "PROXYPIN_QUIC"

        private const val PREFS = "proxypin_root"
        private const val PREF_RULES_INSTALLED = "rulesInstalled"

        /** 每个 multiport 最多 15 个端口 */
        private const val MULTIPORT_MAX = 15
    }

    data class Options(
        val proxyHost: String,
        val proxyPort: Int,
        val allowApps: List<String>,
        val disallowApps: List<String>,
        val proxyPassDomains: List<String>,
        /** 需要重定向的目的端口，空 = 全部 TCP（排除 53） */
        val redirectPorts: List<String>,
        /** 是否拒绝被捕获应用的 IPv6 TCP，迫使其回落到 IPv4 被抓包 */
        val blockIpv6: Boolean,
        /** 是否拒绝被捕获应用的 QUIC(UDP 443)，迫使其回落到 TCP 被抓包 */
        val blockQuic: Boolean,
        /** 是否本机代理（REDIRECT），否则 DNAT 到远程代理 */
        val localProxy: Boolean
    )

    @Volatile
    var isRunning = false
        private set

    @Volatile
    var lastOptions: Options? = null
        private set

    @Volatile
    var lastError: String? = null
        private set

    /** 用户选择了 Root 模式（画中画等原生入口据此决定启动 root 还是 VPN） */
    @Volatile
    var preferRoot = false

    /** srcPort -> entry，短期缓存，避免每个请求都 cat 一遍连接表 */
    private val lookupCache = SimpleCache<Int, TcpConnectionTable.Entry>(10_000, 60, TimeUnit.SECONDS)

    fun isRootAvailable(): Boolean = RootShell.hasSuBinary() && RootShell.instance.requestRoot()

    @Synchronized
    fun start(context: Context, options: Options): Boolean {
        lastError = null
        if (!RootShell.instance.requestRoot()) {
            lastError = "root permission denied"
            return false
        }

        removeRules()
        val commands = try {
            buildRules(context, options)
        } catch (e: Exception) {
            lastError = e.message ?: e.toString()
            return false
        }
        val failed = RootShell.instance.execAll(commands)
        if (failed != null) {
            lastError = failed.stderr.joinToString("\n").ifEmpty { "iptables failed (${failed.exitCode})" }
            Log.e(TAG, "install rules failed: $lastError")
            removeRules()
            return false
        }

        // IPv6 失败不影响主流程（部分内核无 ip6tables REJECT）
        if (options.blockIpv6) {
            RootShell.instance.execAll(buildIpv6Rules(context, options), ignoreError = true)
        }

        if (options.blockQuic) {
            RootShell.instance.execAll(buildQuicRules(context, options, "iptables"), ignoreError = true)
            RootShell.instance.execAll(buildQuicRules(context, options, "ip6tables"), ignoreError = true)
        }

        markInstalled(context, true)
        lookupCache.clear()
        lastOptions = options
        isRunning = true
        Log.i(TAG, "root proxy started $options")
        return true
    }

    @Synchronized
    fun stop(context: Context) {
        if (isRunning || isInstalled(context)) {
            removeRules()
        }
        markInstalled(context, false)
        lookupCache.clear()
        isRunning = false
        Log.i(TAG, "root proxy stopped")
    }

    /** 进程被杀后规则会残留，导致被捕获应用断网；启动时清理 */
    fun cleanupStaleRules(context: Context) {
        if (!isRunning && isInstalled(context)) {
            Log.w(TAG, "found stale iptables rules, cleaning")
            removeRules()
            markInstalled(context, false)
        }
    }

    private fun removeRules() {
        val cmds = listOf(
            "while iptables -w -t nat -D OUTPUT -j $NAT_CHAIN 2>/dev/null; do :; done",
            "iptables -w -t nat -F $NAT_CHAIN 2>/dev/null",
            "iptables -w -t nat -X $NAT_CHAIN 2>/dev/null",
            "while ip6tables -w -t filter -D OUTPUT -j $FILTER6_CHAIN 2>/dev/null; do :; done",
            "ip6tables -w -t filter -F $FILTER6_CHAIN 2>/dev/null",
            "ip6tables -w -t filter -X $FILTER6_CHAIN 2>/dev/null",
            "while iptables -w -t filter -D OUTPUT -j $QUIC_CHAIN 2>/dev/null; do :; done",
            "iptables -w -t filter -F $QUIC_CHAIN 2>/dev/null",
            "iptables -w -t filter -X $QUIC_CHAIN 2>/dev/null",
            "while ip6tables -w -t filter -D OUTPUT -j $QUIC_CHAIN 2>/dev/null; do :; done",
            "ip6tables -w -t filter -F $QUIC_CHAIN 2>/dev/null",
            "ip6tables -w -t filter -X $QUIC_CHAIN 2>/dev/null",
        )
        RootShell.instance.execAll(cmds, ignoreError = true)
    }

    internal fun buildRules(context: Context, o: Options): List<String> {
        val ipt = "iptables -w -t nat"
        val c = NAT_CHAIN
        val rules = ArrayList<String>()
        rules += "$ipt -N $c"
        // 1. 排除 ProxyPin 自身，否则代理的出站连接会被重定向回自己形成环路
        rules += "$ipt -A $c -m owner --uid-owner ${Process.myUid()} -j RETURN"
        // 2. 排除本地/回环
        rules += "$ipt -A $c -d 127.0.0.0/8 -j RETURN"
        rules += "$ipt -A $c -p tcp --dport 53 -j RETURN"
        // 远程代理自身地址不能再被重定向
        if (!o.localProxy) {
            rules += "$ipt -A $c -d ${o.proxyHost} -p tcp --dport ${o.proxyPort} -j RETURN"
        }
        // 3. 代理忽略列表（IP / CIDR / 可解析域名）
        for (dst in resolveBypass(o.proxyPassDomains)) {
            rules += "$ipt -A $c -d $dst -j RETURN"
        }

        val target = if (o.localProxy) "REDIRECT --to-ports ${o.proxyPort}"
        else "DNAT --to-destination ${o.proxyHost}:${o.proxyPort}"
        val portMatches = portMatches(o.redirectPorts)

        val allowUids = uidsOf(context, o.allowApps)
        if (o.allowApps.isNotEmpty()) {
            // 白名单：仅重定向指定应用
            if (allowUids.isEmpty()) {
                throw IllegalStateException("no installed app in whitelist")
            }
            for (uid in allowUids) for (pm in portMatches) {
                rules += "$ipt -A $c -p tcp$pm -m owner --uid-owner $uid -j $target"
            }
        } else {
            // 黑名单：排除指定应用，其余全部重定向
            for (uid in uidsOf(context, o.disallowApps)) {
                rules += "$ipt -A $c -m owner --uid-owner $uid -j RETURN"
            }
            for (pm in portMatches) {
                rules += "$ipt -A $c -p tcp$pm -j $target"
            }
        }
        rules += "$ipt -I OUTPUT -j $c"
        return rules
    }

    private fun buildIpv6Rules(context: Context, o: Options): List<String> {
        val ipt = "ip6tables -w -t filter"
        val c = FILTER6_CHAIN
        val reject = "REJECT --reject-with tcp-reset"
        val rules = ArrayList<String>()
        rules += "$ipt -N $c"
        rules += "$ipt -A $c -m owner --uid-owner ${Process.myUid()} -j RETURN"
        rules += "$ipt -A $c -d ::1/128 -j RETURN"
        rules += "$ipt -A $c -d fe80::/10 -j RETURN"
        rules += "$ipt -A $c -p tcp --dport 53 -j RETURN"
        val portMatches = portMatches(o.redirectPorts)
        if (o.allowApps.isNotEmpty()) {
            for (uid in uidsOf(context, o.allowApps)) for (pm in portMatches) {
                rules += "$ipt -A $c -p tcp$pm -m owner --uid-owner $uid -j $reject"
            }
        } else {
            for (uid in uidsOf(context, o.disallowApps)) {
                rules += "$ipt -A $c -m owner --uid-owner $uid -j RETURN"
            }
            for (pm in portMatches) {
                rules += "$ipt -A $c -p tcp$pm -j $reject"
            }
        }
        rules += "$ipt -I OUTPUT -j $c"
        return rules
    }

    /** 拒绝被捕获应用的 UDP 443（QUIC / HTTP3），客户端会自动回落到 TCP */
    private fun buildQuicRules(context: Context, o: Options, binary: String): List<String> {
        val ipt = "$binary -w -t filter"
        val c = QUIC_CHAIN
        val reject = if (binary == "iptables") "REJECT --reject-with icmp-port-unreachable"
        else "REJECT --reject-with icmp6-port-unreachable"
        val rules = ArrayList<String>()
        rules += "$ipt -N $c"
        rules += "$ipt -A $c -m owner --uid-owner ${Process.myUid()} -j RETURN"
        if (o.allowApps.isNotEmpty()) {
            for (uid in uidsOf(context, o.allowApps)) {
                rules += "$ipt -A $c -p udp --dport 443 -m owner --uid-owner $uid -j $reject"
            }
        } else {
            for (uid in uidsOf(context, o.disallowApps)) {
                rules += "$ipt -A $c -m owner --uid-owner $uid -j RETURN"
            }
            rules += "$ipt -A $c -p udp --dport 443 -j $reject"
        }
        rules += "$ipt -I OUTPUT -j $c"
        return rules
    }

    /** 端口列表 -> 若干个 " -m multiport --dports a,b:c" 片段；空列表表示全部端口 */
    internal fun portMatches(ports: List<String>): List<String> {
        val valid = ports.map { it.trim().replace('-', ':') }
            .filter { it.matches(Regex("^\\d{1,5}(:\\d{1,5})?$")) }
            .distinct()
        if (valid.isEmpty()) return listOf("")
        return valid.chunked(MULTIPORT_MAX).map { " -m multiport --dports ${it.joinToString(",")}" }
    }

    private fun resolveBypass(domains: List<String>): List<String> {
        val result = LinkedHashSet<String>()
        for (raw in domains) {
            val d = raw.trim()
            if (d.isEmpty() || d.contains('*') || d == "localhost") continue
            if (d.matches(Regex("^\\d{1,3}(\\.\\d{1,3}){3}(/\\d{1,2})?$"))) {
                result += d
                continue
            }
            if (d.contains(':')) continue // IPv6 不在 IPv4 nat 表处理
            try {
                InetAddress.getAllByName(d).filter { it.address.size == 4 }
                    .forEach { result += it.hostAddress!! }
            } catch (_: Exception) {
            }
        }
        return result.toList()
    }

    /** 包名 -> uid，包含所有用户（工作资料/分身）下的同一应用 */
    private fun uidsOf(context: Context, packages: List<String>): List<Int> {
        if (packages.isEmpty()) return emptyList()
        val pm = context.packageManager
        val appIds = LinkedHashSet<Int>()
        for (pkg in packages) {
            try {
                val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    pm.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))
                } else {
                    @Suppress("DEPRECATION") pm.getApplicationInfo(pkg, 0)
                }
                appIds += info.uid % 100_000
            } catch (_: Exception) {
                Log.w(TAG, "package not found: $pkg")
            }
        }
        val userIds = listUserIds()
        return appIds.flatMap { appId -> userIds.map { it * 100_000 + appId } }
    }

    private fun listUserIds(): List<Int> {
        val r = RootShell.instance.exec("ls /data/user 2>/dev/null")
        val ids = r.stdout.mapNotNull { it.trim().toIntOrNull() }
        return ids.ifEmpty { listOf(0) }
    }

    /**
     * 按应用的源端口（= 代理侧 accept 到的 remote port）查找应用侧连接。
     */
    fun lookup(sourcePort: Int): TcpConnectionTable.Entry? {
        if (!isRunning) return null
        lookupCache.get(sourcePort)?.let { return it }
        val proxyPort = lastOptions?.proxyPort ?: return null
        val entries = TcpConnectionTable.read()
        var found: TcpConnectionTable.Entry? = null
        for (e in entries) {
            // 代理自身 accept 的 socket（local port 为代理端口）以及 ProxyPin 自己的出站连接跳过
            if (e.localPort == proxyPort || e.uid == Process.myUid()) continue
            if (e.localPort == sourcePort) {
                found = e
                break
            }
        }
        if (found != null) lookupCache.put(sourcePort, found)
        return found
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun isInstalled(context: Context) = prefs(context).getBoolean(PREF_RULES_INSTALLED, false)

    private fun markInstalled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(PREF_RULES_INSTALLED, value).commit()
    }
}
