package com.network.proxy.root

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.network.proxy.MainActivity
import com.network.proxy.R

/**
 * Root 模式前台服务：iptables 规则本身由 [RootProxyManager] 安装，
 * 本服务只负责保活进程（代理核心运行在 App 进程内）以及在被移除/销毁时清理规则，
 * 避免 App 被杀后流量仍被重定向到失效端口导致断网。
 */
class RootProxyService : Service() {
    companion object {
        private const val TAG = "RootProxyService"
        private const val NOTIFICATION_ID = 9528
        private const val CHANNEL_ID = "root-proxy-notifications"
        const val ACTION_START = "ROOT_PROXY_START"
        const val ACTION_STOP = "ROOT_PROXY_STOP"

        fun startIntent(context: Context) =
            Intent(context, RootProxyService::class.java).setAction(ACTION_START)

        fun stopIntent(context: Context) =
            Intent(context, RootProxyService::class.java).setAction(ACTION_STOP)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                Thread { RootProxyManager.instance.stop(applicationContext) }.start()
                ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            else -> {
                showNotification()
                // 系统重建服务（intent == null）时规则可能已不对应当前进程，直接清理退出
                if (intent == null && !RootProxyManager.instance.isRunning) {
                    Thread { RootProxyManager.instance.cleanupStaleRules(applicationContext) }.start()
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.i(TAG, "task removed, keep root proxy running in background")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (RootProxyManager.instance.isRunning) {
            Thread { RootProxyManager.instance.stop(applicationContext) }.start()
        }
    }

    private fun showNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Root Proxy Status", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val contentIntent = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getService(
            this, 1, stopIntent(this), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentIntent)
            .setContentTitle(getString(R.string.root_proxy_notification_title))
            .setContentText(getString(R.string.root_proxy_notification_content))
            .addAction(0, getString(R.string.root_proxy_notification_stop), stopIntent)
            .setOngoing(true)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.w(TAG, "startForeground failed", e)
        }
    }
}
