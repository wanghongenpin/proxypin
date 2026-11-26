package com.network.proxy.plugin

import android.content.Context
import android.util.Log
import com.network.proxy.root.RawCaptureManager
import com.network.proxy.root.RootShell
import com.network.proxy.vpn.util.ProcessInfoManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Root 原始抓包（tcpdump）插件
 *
 * - MethodChannel `com.proxy/rawCapture`：start / stop / status / interfaces / lookupOwner / deleteFile
 * - EventChannel `com.proxy/rawCapture/events`：pcap 字节流（Uint8List），以及 {"event":"stopped"} 状态事件
 */
class RawCapturePlugin : AndroidFlutterPlugin() {
    companion object {
        const val CHANNEL = "com.proxy/rawCapture"
        const val EVENT_CHANNEL = "com.proxy/rawCapture/events"
        private const val TAG = "RawCapturePlugin"
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private lateinit var appContext: Context
    private var eventSink: EventChannel.EventSink? = null
    private val manager = RawCaptureManager.instance

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext

        EventChannel(binding.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        manager.listener = object : RawCaptureManager.Listener {
            override fun onData(bytes: ByteArray) {
                eventSink?.success(bytes)
            }

            override fun onStopped(error: String?, file: String?) {
                eventSink?.success(mapOf("event" to "stopped", "error" to error, "file" to file))
            }
        }

        val channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "running" to manager.isRunning,
                        "file" to manager.currentFile?.absolutePath,
                        "bytes" to manager.capturedBytes,
                        "droppedForUi" to manager.droppedForUi,
                        "bundled" to manager.isBinaryBundled(appContext),
                        "hasSu" to RootShell.hasSuBinary(),
                        "abi" to manager.abi(),
                    )
                )

                "interfaces" -> async(result) { manager.interfaces() }

                "start" -> {
                    val options = RawCaptureManager.Options(
                        iface = call.argument<String>("iface") ?: "any",
                        filter = call.argument<String>("filter") ?: "",
                        snapLen = call.argument<Int>("snapLen") ?: 0,
                    )
                    async(result) {
                        try {
                            mapOf("success" to true, "file" to manager.start(appContext, options).absolutePath)
                        } catch (e: Exception) {
                            Log.w(TAG, "start failed", e)
                            mapOf("success" to false, "error" to (e.message ?: e.toString()))
                        }
                    }
                }

                "stop" -> async(result) { manager.stop() }

                "lookupOwner" -> {
                    val proto = call.argument<String>("proto") ?: "tcp"
                    val srcPort = call.argument<Int>("srcPort") ?: 0
                    val dstPort = call.argument<Int>("dstPort") ?: 0
                    async(result) {
                        val uid = manager.lookupUid(proto, srcPort, dstPort) ?: return@async null
                        val info = ProcessInfoManager.instance.getProcessInfo(uid)
                        mapOf(
                            "uid" to uid,
                            "name" to (info?.get("name")?.toString() ?: systemUidName(uid)),
                            "packageName" to info?.get("packageName"),
                        )
                    }
                }

                "deleteFile" -> {
                    val path = call.argument<String>("path")
                    val ok = path != null && path.startsWith(appContext.cacheDir.absolutePath) && File(path).delete()
                    result.success(ok)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun systemUidName(uid: Int): String? = when (uid) {
        0 -> "root"
        1000 -> "system"
        1021 -> "gps"
        1051 -> "netd (DNS)"
        1052 -> "dns_tether"
        2000 -> "shell"
        else -> null
    }

    private fun async(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            val value = try {
                block()
            } catch (e: Exception) {
                Log.e(TAG, "call failed", e)
                withContext(Dispatchers.Main) { result.error("RAW_CAPTURE_ERROR", e.message, null) }
                return@launch
            }
            withContext(Dispatchers.Main) { result.success(value) }
        }
    }
}
