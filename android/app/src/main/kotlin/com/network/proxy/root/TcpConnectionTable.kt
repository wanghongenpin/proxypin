package com.network.proxy.root

import android.util.Log
import java.io.File

/**
 * 解析 /proc/net/tcp、/proc/net/tcp6。
 *
 * iptables REDIRECT 对发起连接的应用是透明的：应用自己的 socket 在内核连接表中
 * 仍记录着 本地地址:源端口 -> 原始目的地址:端口，以及所属 uid。
 * 代理侧 accept 到的连接的 remote port 即应用的源端口，据此可反查原始目的地址与应用。
 *
 * Android 10+ 普通应用无法读取 /proc/net/tcp，因此优先直接读取，失败时走 root shell。
 */
object TcpConnectionTable {
    private const val TAG = "TcpConnectionTable"

    data class Entry(
        val localHost: String,
        val localPort: Int,
        val remoteHost: String,
        val remotePort: Int,
        val state: Int,
        val uid: Int
    )

    private const val TCP_LISTEN = 0x0A

    @Volatile
    private var directReadable: Boolean? = null

    fun read(): List<Entry> {
        val lines = readRaw()
        val result = ArrayList<Entry>(lines.size)
        for (line in lines) {
            parseLine(line)?.let { result.add(it) }
        }
        return result
    }

    private fun readRaw(): List<String> {
        if (directReadable != false) {
            try {
                val lines = File("/proc/net/tcp").readLines() + File("/proc/net/tcp6").readLines()
                // 部分 ROM 可读但只返回表头
                if (lines.size > 2) {
                    directReadable = true
                    return lines
                }
            } catch (_: Exception) {
            }
            directReadable = false
        }
        val r = RootShell.instance.exec("cat /proc/net/tcp /proc/net/tcp6 2>/dev/null")
        return r.stdout
    }

    internal fun parseLine(raw: String): Entry? {
        val parts = raw.trim().split(Regex("\\s+"))
        // sl local rem st tx:rx tr:when retrnsmt uid ...
        if (parts.size < 8 || !parts[0].endsWith(":")) return null
        return try {
            val (lh, lp) = parseAddress(parts[1])
            val (rh, rp) = parseAddress(parts[2])
            val state = parts[3].toInt(16)
            if (state == TCP_LISTEN) return null
            Entry(lh, lp, rh, rp, state, parts[7].toInt())
        } catch (e: Exception) {
            null
        }
    }

    /** "0100007F:1F90" 或 32 位十六进制 IPv6 */
    internal fun parseAddress(s: String): Pair<String, Int> {
        val idx = s.indexOf(':')
        val hex = s.substring(0, idx)
        val port = s.substring(idx + 1).toInt(16)
        return Pair(decodeIp(hex), port)
    }

    internal fun decodeIp(hex: String): String {
        if (hex.length == 8) {
            return littleEndianWordToIpv4(hex)
        }
        // IPv6：4 个 32 位字，每个字为主机字节序（小端）
        val bytes = ByteArray(16)
        for (w in 0 until 4) {
            val word = hex.substring(w * 8, w * 8 + 8)
            for (b in 0 until 4) {
                bytes[w * 4 + b] = word.substring((3 - b) * 2, (3 - b) * 2 + 2).toInt(16).toByte()
            }
        }
        // IPv4-mapped ::ffff:a.b.c.d
        val mapped = (0 until 10).all { bytes[it].toInt() == 0 } &&
                bytes[10].toInt() and 0xFF == 0xFF && bytes[11].toInt() and 0xFF == 0xFF
        if (mapped) {
            return "${bytes[12].toInt() and 0xFF}.${bytes[13].toInt() and 0xFF}.${bytes[14].toInt() and 0xFF}.${bytes[15].toInt() and 0xFF}"
        }
        return try {
            java.net.InetAddress.getByAddress(bytes).hostAddress ?: hex
        } catch (e: Exception) {
            Log.w(TAG, "decode ipv6 failed $hex", e)
            hex
        }
    }

    private fun littleEndianWordToIpv4(hex: String): String {
        val b0 = hex.substring(6, 8).toInt(16)
        val b1 = hex.substring(4, 6).toInt(16)
        val b2 = hex.substring(2, 4).toInt(16)
        val b3 = hex.substring(0, 2).toInt(16)
        return "$b0.$b1.$b2.$b3"
    }
}
