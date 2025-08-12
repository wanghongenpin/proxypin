package com.network.proxy.plugin

import com.network.proxy.vpn.util.ProcessInfoManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 进程信息插件
 *
 * @author wanghongen
 */
class ProcessInfoPlugin : AndroidFlutterPlugin() {
    private val processInfoManager = ProcessInfoManager.instance

    companion object {
        const val CHANNEL = "com.proxy/processInfo"
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        super.onAttachedToActivity(binding)
        processInfoManager.activity = binding.activity
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getProcessByPort" -> {
                    val host = call.argument<String>("host")
                    val port = call.argument<Int>("port")
                    if (port != null) {
                        CoroutineScope(Dispatchers.IO).launch {
                            val appInfo = processInfoManager.getProcessInfoByPort(host, port)
                            withContext(Dispatchers.Main) {
                                result.success(appInfo)
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "Port is null", null)
                    }
                }

                "getRemoteAddressByPort" -> {
                    val port = call.argument<Int>("port")
                    result.success(processInfoManager.getRemoteAddressByPort(port!!))
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }


}