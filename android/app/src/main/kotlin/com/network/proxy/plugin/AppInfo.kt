package com.network.proxy.plugin

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import java.io.ByteArrayOutputStream

class ProcessInfo(name: CharSequence, packageName: String, icon: ByteArray?, versionName: String?) :
    HashMap<String, Any?>() {
    init {
        put("name", name)
        put("packageName", packageName)
        put("icon", icon)
        put("versionName", versionName)
    }

    fun copy(): ProcessInfo {
        val name = this["name"] as? CharSequence ?: ""
        val packageName = this["packageName"] as? String ?: ""
        val icon = this["icon"] as? ByteArray
        val versionName = this["versionName"] as? String
        val newInfo = ProcessInfo(name, packageName, icon, versionName)
        newInfo.putAll(this)
        return newInfo
    }

    companion object {
        fun create(
            packageManager: PackageManager,
            app: ApplicationInfo,
            withIcon: Boolean = true
        ): ProcessInfo {
            val name = packageManager.getApplicationLabel(app)
            val packageName = app.packageName
            val icon =
                if (withIcon) drawableToByteArray(app.loadIcon(packageManager)) else ByteArray(0)
            val packageInfo = packageManager.getPackageInfo(app.packageName, 0)
            // 部分应用可能没有设置versionName，将导致获取列表操作失败
            val versionName = packageInfo.versionName ?: ""

            return ProcessInfo(name, packageName, icon, versionName)
        }

        private fun drawableToByteArray(drawable: Drawable): ByteArray {
            val bitmap = drawableToBitmap(drawable)
            val stream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
            return stream.toByteArray()
        }

        private fun drawableToBitmap(drawable: Drawable): Bitmap {
            if (drawable is BitmapDrawable) {
                return drawable.bitmap
            }
            val bitmap = Bitmap.createBitmap(
                drawable.intrinsicWidth,
                drawable.intrinsicHeight,
                Bitmap.Config.ARGB_8888
            )
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }

    }

}