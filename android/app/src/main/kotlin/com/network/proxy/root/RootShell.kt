package com.network.proxy.root

import android.util.Log
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * 常驻 root shell。
 *
 * 每次 `su -c` 都会 fork 新进程并可能触发授权弹窗，查连接表这种高频操作开销太大；
 * 这里保持一个 `su` 进程，用随机结束标记分隔每条命令的输出。
 *
 * @author proxypin root mode
 */
class RootShell private constructor() {
    companion object {
        private const val TAG = "RootShell"
        val instance = RootShell()

        private val SU_PATHS = arrayOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su",
            "/debug_ramdisk/su", "/data/adb/ksu/bin/su", "/data/adb/ap/bin/su"
        )

        /** 是否存在 su 可执行文件（不触发授权） */
        fun hasSuBinary(): Boolean {
            if (SU_PATHS.any { File(it).exists() }) return true
            val path = System.getenv("PATH") ?: return false
            return path.split(":").any { File(it, "su").exists() }
        }
    }

    class Result(val exitCode: Int, val stdout: List<String>, val stderr: List<String>) {
        val isSuccess get() = exitCode == 0
        override fun toString() = "exit=$exitCode out=$stdout err=$stderr"
    }

    private var process: Process? = null
    private var writer: OutputStreamWriter? = null
    private var reader: BufferedReader? = null
    private var errReader: BufferedReader? = null

    @Synchronized
    private fun ensureShell(): Boolean {
        val p = process
        if (p != null && p.isAliveCompat()) return true
        close()
        return try {
            val newProcess = ProcessBuilder("su").start()
            process = newProcess
            writer = OutputStreamWriter(newProcess.outputStream)
            reader = BufferedReader(InputStreamReader(newProcess.inputStream))
            errReader = BufferedReader(InputStreamReader(newProcess.errorStream))
            // 校验确实拿到了 uid 0
            val id = execInternal("id -u")
            val ok = id != null && id.stdout.firstOrNull()?.trim() == "0"
            if (!ok) {
                Log.w(TAG, "su granted but uid != 0: $id")
                close()
            }
            ok
        } catch (e: Exception) {
            Log.w(TAG, "start su failed", e)
            close()
            false
        }
    }

    /** su shell 已建立（不会触发授权弹窗） */
    val isReady: Boolean get() = process?.isAliveCompat() == true

    /** 请求 root 权限（首次会触发 Magisk/KernelSU 等授权弹窗） */
    fun requestRoot(): Boolean = ensureShell()

    @Synchronized
    fun exec(command: String): Result {
        if (!ensureShell()) return Result(-1, emptyList(), listOf("root not available"))
        return execInternal(command) ?: run {
            close()
            Result(-1, emptyList(), listOf("root shell died"))
        }
    }

    /** 依次执行多条命令，返回第一个失败的结果；全部成功返回 null */
    @Synchronized
    fun execAll(commands: List<String>, ignoreError: Boolean = false): Result? {
        for (cmd in commands) {
            val r = exec(cmd)
            if (!r.isSuccess) {
                Log.w(TAG, "command failed: $cmd -> $r")
                if (!ignoreError) return r
            }
        }
        return null
    }

    private fun execInternal(command: String): Result? {
        val w = writer ?: return null
        val r = reader ?: return null
        val er = errReader ?: return null
        val marker = "__PP_END_" + UUID.randomUUID().toString().replace("-", "")
        return try {
            // stderr 也加标记，保证读取与命令一一对应
            w.write("$command\n__pp_rc=\$?\necho \"$marker \$__pp_rc\"\necho \"$marker\" >&2\n")
            w.flush()

            val out = ArrayList<String>()
            var exitCode = -1
            while (true) {
                val line = r.readLine() ?: return null
                if (line.startsWith(marker)) {
                    exitCode = line.substring(marker.length).trim().toIntOrNull() ?: -1
                    break
                }
                out.add(line)
            }
            val err = ArrayList<String>()
            while (true) {
                val line = er.readLine() ?: break
                if (line == marker) break
                err.add(line)
            }
            Result(exitCode, out, err)
        } catch (e: Exception) {
            Log.w(TAG, "exec failed: $command", e)
            null
        }
    }

    @Synchronized
    fun close() {
        try {
            writer?.write("exit\n")
            writer?.flush()
        } catch (_: Exception) {
        }
        try {
            process?.destroy()
        } catch (_: Exception) {
        }
        process = null
        writer = null
        reader = null
        errReader = null
    }

    private fun Process.isAliveCompat(): Boolean {
        return try {
            exitValue()
            false
        } catch (_: IllegalThreadStateException) {
            true
        }
    }
}
