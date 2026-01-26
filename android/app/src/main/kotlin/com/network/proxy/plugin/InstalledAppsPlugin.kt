package com.network.proxy.plugin

import android.content.pm.ApplicationInfo
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * 已经安装应用列表
 *
 * @author wanghongen
 */
class InstalledAppsPlugin : AndroidFlutterPlugin() {
    var channel: MethodChannel? = null

    companion object {
        const val CHANNEL = "com.proxy/installedApps"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)

        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    val withIcon = call.argument<Boolean>("withIcon") ?: false
                    val packageNamePrefix = call.argument<String>("packageNamePrefix") ?: ""
                    val includeSystemApps = call.argument<Boolean>("includeSystemApps") ?: false
                    Thread {
                        result.success(
                            getInstalledApps(
                                withIcon,
                                packageNamePrefix,
                                includeSystemApps
                            )
                        )
                    }.start()
                }

                "getAppInfo" -> {
                    val packageName = call.argument<String>("packageName") ?: ""
                    result.success(getAppInfo(packageName))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun getAppInfo(packageName: String): ProcessInfo {
        val packageManager = activity.packageManager
        packageManager.getApplicationInfo(packageName, 0).let { app ->
            return ProcessInfo.create(packageManager, app, true)
        }
    }

    private fun isSystemApp(applicationInfo: ApplicationInfo?): Boolean {
        if (applicationInfo == null) return false
        return (applicationInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
    }

    private fun getInstalledApps(
        withIcon: Boolean,
        packageNamePrefix: String,
        includeSystemApps: Boolean
    ): List<ProcessInfo> {
        val packageManager = activity.packageManager
        var installedApps = packageManager.getInstalledApplications(0)

        if (!includeSystemApps) {
            installedApps =
                installedApps.filter { app -> !isSystemApp(app) }
        }

        if (packageNamePrefix.isNotEmpty()) {
            installedApps = installedApps.filter { app ->
                app.packageName.startsWith(
                    packageNamePrefix.lowercase(Locale.ENGLISH)
                )
            }
        }

        val threadPoolExecutor = Executors.newFixedThreadPool(4)
        installedApps.map { app ->
            val task: Callable<ProcessInfo> = Callable {
                ProcessInfo.create(packageManager, app, withIcon)
            }
            threadPoolExecutor.submit(task)
        }.map { future ->
            future.get()
        }.let {
            threadPoolExecutor.shutdown()
            threadPoolExecutor.awaitTermination(3, TimeUnit.SECONDS)
            return it
        }
    }

}
