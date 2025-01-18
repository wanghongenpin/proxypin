package com.network.proxy.plugin

import com.network.proxy.ProxyVpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class VpnServicePlugin : AndroidFlutterPlugin() {
    companion object {
        const val CHANNEL = "com.proxy/proxyVpn"
        const val REQUEST_CODE: Int = 24
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isRunning" -> {
                    result.success(ProxyVpnService.isRunning)
                }

                "startVpn" -> {
                    val host = call.argument<String>("proxyHost")
                    val port = call.argument<Int>("proxyPort")
                    val allowApps = call.argument<ArrayList<String>>("allowApps")
                    val disallowApps = call.argument<ArrayList<String>>("disallowApps")
                    val prepareVpn = ProxyVpnService.prepareVpn(activity, host!!, port!!, allowApps, disallowApps)
                    if (prepareVpn) {
                        startVpn(host, port, allowApps, disallowApps)
                    }
                    result.success(prepareVpn)
                }

                "stopVpn" -> {
                    stopVpn()
                    result.success(null)
                }

                "restartVpn" -> {
                    val host = call.argument<String>("proxyHost")
                    val port = call.argument<Int>("proxyPort")
                    val allowApps = call.argument<ArrayList<String>>("allowApps")
                    val disallowApps = call.argument<ArrayList<String>>("disallowApps")
                    stopVpn()
                    startVpn(host!!, port!!, allowApps, disallowApps)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * 启动vpn服务
     */
    private fun startVpn(
        host: String,
        port: Int,
        allowApps: ArrayList<String>? = arrayListOf(),
        disallowApps: ArrayList<String>? = arrayListOf(),
    ) {
        val intent = ProxyVpnService.startVpnIntent(activity, host, port, allowApps, disallowApps)
        activity.startService(intent)
    }

    /**
     * 停止vpn服务
     */
    private fun stopVpn() {
        activity.startService(ProxyVpnService.stopVpnIntent(activity))
    }
}