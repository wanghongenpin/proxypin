package com.network.proxy.root

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * 原始抓包：以 root 运行内置 tcpdump，pcap 流从 stdout 读出，
 * 同时写入文件（完整数据，供导出）并分批推送给 Dart 侧解析展示。
 */
class RawCaptureManager private constructor() {
    companion object {
        private const val TAG = "RawCapture"
        val instance = RawCaptureManager()

        private const val BIN_NAME = "tcpdump"
        private const val FALLBACK_DIR = "/data/local/tmp"

        /** 推送给 Dart 的批次间隔 / 大小 */
        private const val FLUSH_INTERVAL_MS = 200L
        private const val FLUSH_BYTES = 256 * 1024

        /** Dart 侧处理不过来时最多积压的字节，超过则只写文件不推送 */
        private const val MAX_PENDING_BYTES = 8 * 1024 * 1024

        fun shellQuote(s: String) = "'" + s.replace("'", "'\\''") + "'"
    }

    data class Options(
        val iface: String = "any",
        val filter: String = "",
        val snapLen: Int = 0,
    )

    interface Listener {
        fun onData(bytes: ByteArray)
        fun onStopped(error: String?, file: String?)
    }

    @Volatile
    var isRunning = false
        private set

    @Volatile
    var currentFile: File? = null
        private set

    @Volatile
    var listener: Listener? = null

    @Volatile
    var droppedForUi = 0L
        private set

    @Volatile
    var capturedBytes = 0L
        private set

    private var process: Process? = null
    private var pid: Int? = null
    private var readerThread: Thread? = null
    private val stderrLines = ArrayList<String>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun abi(): String? {
        return Build.SUPPORTED_ABIS.firstOrNull { it == "arm64-v8a" || it == "armeabi-v7a" || it == "x86_64" }
    }

    fun isBinaryBundled(context: Context): Boolean {
        val abi = abi() ?: return false
        return try {
            context.assets.open("tcpdump/$abi/$BIN_NAME").close()
            true
        } catch (_: Exception) {
            false
        }
    }

    /** 从 assets 解压 tcpdump 到私有目录（按 APK 更新时间判断是否需要覆盖） */
    private fun extractBinary(context: Context): File {
        val abi = abi() ?: throw IllegalStateException("unsupported abi: ${Build.SUPPORTED_ABIS.joinToString()}")
        val dir = File(context.filesDir, "bin").apply { mkdirs() }
        val bin = File(dir, BIN_NAME)
        val stamp = File(dir, "$BIN_NAME.stamp")
        val version = try {
            context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime.toString()
        } catch (_: Exception) {
            "0"
        }
        if (!bin.exists() || !stamp.exists() || stamp.readText() != version) {
            context.assets.open("tcpdump/$abi/$BIN_NAME").use { input ->
                FileOutputStream(bin).use { input.copyTo(it) }
            }
            bin.setExecutable(true, false)
            bin.setReadable(true, false)
            stamp.writeText(version)
        }
        return bin
    }

    /** 列出网卡 */
    fun interfaces(): List<String> {
        val local = File("/sys/class/net").list()?.toList()
        val names = if (!local.isNullOrEmpty()) local else RootShell.instance.exec("ls /sys/class/net").stdout
        return listOf("any") + names.map { it.trim() }.filter { it.isNotEmpty() }.sorted()
    }

    @Synchronized
    fun start(context: Context, options: Options): File {
        if (isRunning) throw IllegalStateException("already running")
        if (!RootShell.instance.requestRoot()) throw IllegalStateException("root permission denied")

        val bin = extractBinary(context)
        val dir = File(context.cacheDir, "pcap").apply { mkdirs() }
        // 只保留最近 10 个抓包文件
        dir.listFiles()?.sortedByDescending { it.lastModified() }?.drop(10)?.forEach { it.delete() }
        val file = File(dir, "capture-" + SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date()) + ".pcap")

        var error = launch(bin.absolutePath, options, file)
        if (error != null && (error.contains("denied", true) || error.contains("not found", true) ||
                    error.contains("No such file", true))
        ) {
            // 部分 ROM 的 SELinux 不允许执行应用私有目录下的文件，复制到 /data/local/tmp 重试
            Log.w(TAG, "exec from app dir failed ($error), retry from $FALLBACK_DIR")
            val target = "$FALLBACK_DIR/proxypin-$BIN_NAME"
            RootShell.instance.exec("cp ${shellQuote(bin.absolutePath)} $target && chmod 755 $target")
            error = launch(target, options, file)
        }
        if (error != null) {
            file.delete()
            throw IllegalStateException(error)
        }
        return file
    }

    /** 启动 tcpdump；返回错误信息，成功返回 null */
    private fun launch(binPath: String, o: Options, file: File): String? {
        val args = StringBuilder()
        args.append(shellQuote(binPath))
        args.append(" -i ").append(shellQuote(o.iface))
        args.append(" -U -n -s ").append(if (o.snapLen > 0) o.snapLen else 0)
        args.append(" -w -")
        if (o.filter.isNotBlank()) args.append(' ').append(shellQuote(o.filter.trim()))
        val cmd = "echo PID:\$\$ >&2; exec $args"
        Log.i(TAG, "launch: $cmd")

        stderrLines.clear()
        val p = try {
            ProcessBuilder("su", "-c", cmd).start()
        } catch (e: Exception) {
            return e.message ?: e.toString()
        }

        // stderr：首行是 pid，随后是 tcpdump 的状态/错误输出
        val stderrThread = Thread({
            try {
                BufferedReader(InputStreamReader(p.errorStream)).use { r ->
                    while (true) {
                        val line = r.readLine() ?: break
                        if (line.startsWith("PID:")) {
                            pid = line.substring(4).trim().toIntOrNull()
                        } else {
                            Log.i(TAG, "tcpdump: $line")
                            synchronized(stderrLines) { stderrLines.add(line) }
                        }
                    }
                }
            } catch (_: Exception) {
            }
        }, "tcpdump-stderr")
        stderrThread.isDaemon = true
        stderrThread.start()

        // 等待 tcpdump 打印 listening 或退出
        val deadline = System.currentTimeMillis() + 5000
        while (System.currentTimeMillis() < deadline) {
            if (!p.isAliveCompat()) {
                stderrThread.join(500)
                return synchronized(stderrLines) { stderrLines.joinToString("\n") }.ifEmpty { "tcpdump exited (${p.exitValue()})" }
            }
            if (synchronized(stderrLines) { stderrLines.any { it.contains("listening on") } }) break
            Thread.sleep(50)
        }

        process = p
        currentFile = file
        droppedForUi = 0
        capturedBytes = 0
        isRunning = true
        startReader(p, file)
        return null
    }

    private fun startReader(p: Process, file: File) {
        readerThread = Thread({
            var error: String? = null
            val pending = ByteArrayOutputStream()
            var lastFlush = System.currentTimeMillis()
            try {
                FileOutputStream(file).use { out ->
                    val input = p.inputStream
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        capturedBytes += n
                        if (pending.size() < MAX_PENDING_BYTES) {
                            pending.write(buf, 0, n)
                        } else {
                            droppedForUi += n
                        }
                        val now = System.currentTimeMillis()
                        if (pending.size() >= FLUSH_BYTES || now - lastFlush >= FLUSH_INTERVAL_MS) {
                            out.flush()
                            dispatch(pending)
                            lastFlush = now
                        }
                    }
                    out.flush()
                }
            } catch (e: Exception) {
                if (isRunning) error = e.message
            }
            dispatch(pending)
            val exit = try {
                p.waitFor(1, TimeUnit.SECONDS); p.exitValue()
            } catch (_: Exception) {
                -1
            }
            if (error == null && exit != 0 && isRunning) {
                error = synchronized(stderrLines) { stderrLines.lastOrNull() } ?: "tcpdump exited ($exit)"
            }
            val f = currentFile?.absolutePath
            isRunning = false
            process = null
            pid = null
            mainHandler.post { listener?.onStopped(error, f) }
        }, "tcpdump-reader")
        readerThread!!.start()
    }

    private fun dispatch(pending: ByteArrayOutputStream) {
        if (pending.size() == 0) return
        val bytes = pending.toByteArray()
        pending.reset()
        mainHandler.post { listener?.onData(bytes) }
    }

    /** 停止抓包，返回 pcap 文件路径 */
    fun stop(): String? {
        val p = process
        val file = currentFile?.absolutePath
        if (p == null) return file
        isRunning = false
        // SIGINT 让 tcpdump 正常刷新缓冲后退出
        pid?.let { RootShell.instance.exec("kill -INT $it 2>/dev/null") }
        readerThread?.join(3000)
        if (p.isAliveCompat()) {
            pid?.let { RootShell.instance.exec("kill -9 $it 2>/dev/null") }
            p.destroy()
        }
        return file
    }

    /**
     * 根据五元组查找所属应用 uid。UDP 套接字常为未连接状态（远端 0），只按本地端口匹配。
     */
    fun lookupUid(proto: String, srcPort: Int, dstPort: Int): Int? {
        val entries = cachedTable(proto)
        fun match(local: Int, remote: Int) =
            entries.firstOrNull { it.localPort == local && it.remotePort == remote }
                ?: entries.firstOrNull { it.localPort == local && it.remotePort == 0 }
        return (match(srcPort, dstPort) ?: match(dstPort, srcPort))?.uid
    }

    private val tableCache = HashMap<String, Pair<Long, List<TcpConnectionTable.Entry>>>()

    @Synchronized
    private fun cachedTable(proto: String): List<TcpConnectionTable.Entry> {
        val now = System.currentTimeMillis()
        tableCache[proto]?.let { if (now - it.first < 1000) return it.second }
        val table = TcpConnectionTable.read(proto)
        tableCache[proto] = now to table
        return table
    }

    private fun Process.isAliveCompat(): Boolean = try {
        exitValue(); false
    } catch (_: IllegalThreadStateException) {
        true
    }
}
