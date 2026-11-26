package com.network.proxy.plugin

import android.content.Context
import android.os.Build
import android.util.Log
import com.network.proxy.root.RootProxyManager
import com.network.proxy.root.RootProxyService
import com.network.proxy.root.RootShell
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetAddress
import java.net.NetworkInterface

/**
 * Root 模式（iptables 透明代理）插件
 */
class RootProxyPlugin : AndroidFlutterPlugin() {
    companion object {
        const val CHANNEL = "com.proxy/rootProxy"
        private const val TAG = "RootProxyPlugin"

        fun optionsFrom(call: MethodCall): RootProxyManager.Options {
            val host = call.argument<String>("proxyHost") ?: "127.0.0.1"
            return RootProxyManager.Options(
                proxyHost = host,
                proxyPort = call.argument<Int>("proxyPort") ?: 9099,
                allowApps = call.argument<List<String>>("allowApps") ?: emptyList(),
                disallowApps = call.argument<List<String>>("disallowApps") ?: emptyList(),
                proxyPassDomains = call.argument<List<String>>("proxyPassDomains") ?: emptyList(),
                redirectPorts = call.argument<List<String>>("redirectPorts") ?: emptyList(),
                blockIpv6 = call.argument<Boolean>("blockIpv6") ?: true,
                blockQuic = call.argument<Boolean>("blockQuic") ?: true,
                localProxy = isLocalHost(host)
            )
        }

        private fun isLocalHost(host: String): Boolean = try {
            val target = InetAddress.getByName(host)
            target.isLoopbackAddress || target.isAnyLocalAddress ||
                    NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
                        .any { nif -> nif.inetAddresses.toList().any { it == target } }
        } catch (e: Exception) {
            false
        }

        /** 启动规则并拉起保活服务，必须在后台线程调用 */
        fun startBlocking(context: Context, options: RootProxyManager.Options): Boolean {
            val ok = RootProxyManager.instance.start(context, options)
            if (ok) {
                val intent = RootProxyService.startIntent(context)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "start RootProxyService failed", e)
                }
            }
            return ok
        }

        fun stopBlocking(context: Context) {
            RootProxyManager.instance.stop(context)
            try {
                context.stopService(android.content.Intent(context, RootProxyService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "stop RootProxyService failed", e)
            }
        }
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        // 上次进程被杀残留的规则会导致被捕获应用断网，启动即清理（仅在曾安装过规则时才会调用 su）
        scope.launch { RootProxyManager.instance.cleanupStaleRules(appContext) }

        val channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isRunning" -> result.success(RootProxyManager.instance.isRunning)

                "hasSuBinary" -> result.success(RootShell.hasSuBinary())

                "isRootAvailable" -> async(result) { RootProxyManager.instance.isRootAvailable() }

                "start" -> {
                    val options = optionsFrom(call)
                    async(result) {
                        RootProxyManager.instance.preferRoot = true
                        mapOf(
                            "success" to startBlocking(appContext, options),
                            "error" to RootProxyManager.instance.lastError
                        )
                    }
                }

                "restart" -> {
                    val options = optionsFrom(call)
                    async(result) {
                        mapOf(
                            "success" to startBlocking(appContext, options),
                            "error" to RootProxyManager.instance.lastError
                        )
                    }
                }

                "stop" -> async(result) { stopBlocking(appContext); null }

                else -> result.notImplemented()
            }
        }
    }

    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        scope.launch {
            val value = try {
                block()
            } catch (e: Exception) {
                Log.e(TAG, "root call failed", e)
                withContext(Dispatchers.Main) { result.error("ROOT_ERROR", e.message, null) }
                return@launch
            }
            withContext(Dispatchers.Main) { result.success(value) }
        }
    }
}
