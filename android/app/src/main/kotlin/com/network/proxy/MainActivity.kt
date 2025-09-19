package com.network.proxy

import android.content.Intent
import android.content.res.Configuration
import com.network.proxy.plugin.AppLifecyclePlugin
import com.network.proxy.plugin.InstalledAppsPlugin
import com.network.proxy.plugin.PictureInPicturePlugin
import com.network.proxy.plugin.ProcessInfoPlugin
import com.network.proxy.plugin.VpnServicePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine


class MainActivity : FlutterActivity() {
    private val lifecycleChannel: AppLifecyclePlugin = AppLifecyclePlugin()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pluginRegister(flutterEngine)
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        lifecycleChannel.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration?
    ) {
        lifecycleChannel.onPictureInPictureModeChanged(isInPictureInPictureMode)
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    /**
     * 注册插件
     */
    private fun pluginRegister(flutterEngine: FlutterEngine) {
        flutterEngine.plugins.add(VpnServicePlugin())
        flutterEngine.plugins.add(PictureInPicturePlugin())
        flutterEngine.plugins.add(lifecycleChannel)
        flutterEngine.plugins.add(InstalledAppsPlugin())
        flutterEngine.plugins.add(ProcessInfoPlugin())
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == VpnServicePlugin.REQUEST_CODE) {
            if (resultCode == RESULT_OK) {
                activity.startService(ProxyVpnService.startVpnIntent(activity))
                return
            }

            val alertDialog = Intent(applicationContext, VpnAlertDialog::class.java)
                .setAction("com.network.proxy.ProxyVpnService")
            alertDialog.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(alertDialog)
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
//        activity.startService(ProxyVpnService.stopVpnIntent(activity))
        super.onDestroy()
    }

}
