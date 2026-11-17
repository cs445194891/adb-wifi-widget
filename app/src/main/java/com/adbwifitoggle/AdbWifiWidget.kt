package com.adbwifitoggle

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Home-screen widget for controlling wireless ADB (ADB over TLS) on a rooted device.
 *
 * The control/keepalive scripts are shipped as APK assets and self-deployed into
 * the app's private files dir on first run (no root needed to write our own dir).
 * Root is obtained via Magisk su to execute the script:
 *   <filesDir>/adb_wifi_ctl.sh {toggle|status}
 *
 * Uninstall-safe: scripts live in the private dir, so uninstalling the APK
 * (adb OR via Settings/launcher) removes them; the daemon detects its own file
 * is gone and exits. No service.d / boot receiver / foreground service at all.
 *
 * All su calls run off the main thread via goAsync() to avoid ANR.
 */
class AdbWifiWidget : AppWidgetProvider() {

    companion object {
        private const val ACTION_TOGGLE = "com.adbwifitoggle.TOGGLE"
        private const val ACTION_REFRESH = "com.adbwifitoggle.REFRESH"

        private const val REQ_TOGGLE = 1
        private const val REQ_REFRESH = 2

        // Bump together with versionCode in build.gradle.kts when a script
        // changes, so ensureDeployed() overwrites the on-device copy.
        private const val SCRIPTS_VERSION = 4
        private const val ASSET_CTL = "adb_wifi_ctl.sh"
        private const val ASSET_DAEMON = "adb_wifi_daemon.sh"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val result = goAsync()
        Thread {
            try {
                ensureDeployed(context)
                appWidgetIds.forEach { render(context, appWidgetManager, it) }
            } finally {
                result.finish()
            }
        }.start()
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TOGGLE, ACTION_REFRESH -> {
                val result = goAsync()
                Thread {
                    try {
                        ensureDeployed(context)
                        if (intent.action == ACTION_TOGGLE) {
                            runRoot("${ctlPath(context)} toggle")
                        }
                        refreshAll(context)
                    } finally {
                        result.finish()
                    }
                }.start()
            }
            else -> super.onReceive(context, intent)
        }
    }

    private fun refreshAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(ComponentName(context, AdbWifiWidget::class.java))
        ids.forEach { render(context, mgr, it) }
    }

    /** Render one widget instance: read state via root, then push RemoteViews. */
    private fun render(context: Context, mgr: AppWidgetManager, id: Int) {
        val raw = runRoot("${ctlPath(context)} status")
        val s = parseKv(raw)

        val enabled = s["enabled"] == "1"
        val daemon = s["daemon"] == "1"
        val ip = s["ip"] ?: "--"
        val port = s["port"] ?: "--"
        val ssid = s["ssid"] ?: "--"

        val views = RemoteViews(context.packageName, R.layout.widget)

        views.setTextViewText(R.id.tvState, if (enabled) "开启" else "关闭")
        views.setImageViewResource(
            R.id.ivSwitch,
            if (enabled) R.drawable.switch_on else R.drawable.switch_off
        )
        views.setTextViewText(
            R.id.tvDaemon,
            if (daemon) "运行中" else "已停止"
        )

        views.setTextViewText(R.id.tvIp, ip)
        views.setTextViewText(R.id.tvPort, port)
        views.setTextViewText(R.id.tvSsid, ssid)

        val togglePi = PendingIntent.getBroadcast(
            context, REQ_TOGGLE,
            Intent(context, AdbWifiWidget::class.java).apply { action = ACTION_TOGGLE },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.switchArea, togglePi)

        val refreshPi = PendingIntent.getBroadcast(
            context, REQ_REFRESH,
            Intent(context, AdbWifiWidget::class.java).apply { action = ACTION_REFRESH },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.infoArea, refreshPi)

        mgr.updateAppWidget(id, views)
    }

    private fun ctlPath(context: Context): String =
        File(context.filesDir, ASSET_CTL).absolutePath

    /**
     * Deploy bundled scripts into our private files dir. The app can write and
     * chmod its own files without root (verified on-device). Redeploy when the
     * bundled version is newer. Failure is non-fatal: status then shows "--".
     */
    private fun ensureDeployed(context: Context) {
        val dir = context.filesDir
        val verFile = File(dir, ".scripts_version")
        val ctl = File(dir, ASSET_CTL)
        val daemon = File(dir, ASSET_DAEMON)

        val current = try {
            verFile.readText().trim().toInt()
        } catch (t: Throwable) {
            -1
        }
        if (current == SCRIPTS_VERSION && ctl.exists() && daemon.exists()) return

        try {
            for ((asset, dst) in arrayOf(ASSET_CTL to ctl, ASSET_DAEMON to daemon)) {
                context.assets.open(asset).use { input ->
                    dst.outputStream().use { out -> input.copyTo(out) }
                }
                dst.setExecutable(true, false)
                dst.setReadable(true, false)
            }
            verFile.writeText(SCRIPTS_VERSION.toString())
        } catch (t: Throwable) {
            // Leave old files in place; status will surface any problem.
        }
    }

    private fun parseKv(raw: String): Map<String, String> {
        val out = HashMap<String, String>()
        raw.lineSequence().forEach { line ->
            val i = line.indexOf('=')
            if (i > 0) out[line.substring(0, i).trim()] = line.substring(i + 1).trim()
        }
        return out
    }

    /** Execute as root via `su -c`; must be called off the main thread. */
    private fun runRoot(command: String, timeoutMs: Long = 5000): String {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))
            val stdout = process.inputStream.bufferedReader().use { it.readText() }
            val finished = process.waitFor(timeoutMs, TimeUnit.MILLISECONDS)
            if (!finished) {
                process.destroyForcibly()
                ""
            } else {
                stdout.trim()
            }
        } catch (t: Throwable) {
            ""
        }
    }
}
