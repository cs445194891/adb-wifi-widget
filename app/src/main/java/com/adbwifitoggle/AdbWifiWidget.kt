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
 * Home-screen widget for controlling developer mode / USB debugging /
 * wireless ADB (ADB over TLS) on a rooted device.
 *
 * Scripts are shipped as APK assets and self-deployed into the app's private
 * files dir on first run. Root is via Magisk su:
 *   <filesDir>/adb_wifi_ctl.sh {dev_toggle|usb_toggle|wifi_toggle|status}
 *
 * Uninstall-safe: scripts live in the private dir, so uninstall removes them;
 * the daemon exits when its own file disappears. No service.d / boot receiver.
 *
 * Optimistic UI: on a switch tap, the target switch image/label is pushed
 * immediately (partiallyUpdateAppWidget) so the toggle moves without waiting
 * for the su prompt; once the root command returns, the real state is rendered.
 */
class AdbWifiWidget : AppWidgetProvider() {

    companion object {
        private const val ACTION_DEV = "com.adbwifitoggle.DEV"
        private const val ACTION_USB = "com.adbwifitoggle.USB"
        private const val ACTION_WIFI = "com.adbwifitoggle.WIFI"
        private const val ACTION_REFRESH = "com.adbwifitoggle.REFRESH"
        private const val EXTRA_TARGET = "target"

        private const val REQ_DEV = 1
        private const val REQ_USB = 2
        private const val REQ_WIFI = 3
        private const val REQ_REFRESH = 4

        // Bump with versionCode when a bundled script changes.
        private const val SCRIPTS_VERSION = 6
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
            ACTION_DEV, ACTION_USB, ACTION_WIFI -> {
                // 1) Optimistic update on the main thread: move the tapped switch now.
                val target = intent.getIntExtra(EXTRA_TARGET, -1)
                applyOptimistic(context, intent.action, target)

                // 2) Run the root command off-thread, then render the real state.
                val result = goAsync()
                Thread {
                    try {
                        ensureDeployed(context)
                        val cmd = when (intent.action) {
                            ACTION_DEV -> "dev_toggle"
                            ACTION_USB -> "usb_toggle"
                            ACTION_WIFI -> "wifi_toggle"
                            else -> null
                        }
                        if (cmd != null) runRoot("${ctlPath(context)} $cmd")
                        refreshAll(context)
                    } finally {
                        result.finish()
                    }
                }.start()
            }
            ACTION_REFRESH -> {
                val result = goAsync()
                Thread {
                    try {
                        ensureDeployed(context)
                        refreshAll(context)
                    } finally {
                        result.finish()
                    }
                }.start()
            }
            else -> super.onReceive(context, intent)
        }
    }

    /** Push only the tapped switch's visual so it moves before su returns. */
    private fun applyOptimistic(context: Context, action: String?, target: Int) {
        if (target != 0 && target != 1) return
        val on = target == 1
        val mgr = AppWidgetManager.getInstance(context)
        val ids = mgr.getAppWidgetIds(ComponentName(context, AdbWifiWidget::class.java))
        if (ids.isEmpty()) return
        val drawable = if (on) R.drawable.switch_on else R.drawable.switch_off
        val label = if (on) "开启" else "关闭"
        val views = RemoteViews(context.packageName, R.layout.widget)
        when (action) {
            ACTION_DEV -> {
                views.setImageViewResource(R.id.ivDevSwitch, drawable)
                views.setTextViewText(R.id.tvDevState, label)
            }
            ACTION_USB -> {
                views.setImageViewResource(R.id.ivUsbSwitch, drawable)
                views.setTextViewText(R.id.tvUsbState, label)
            }
            ACTION_WIFI -> {
                views.setImageViewResource(R.id.ivWifiSwitch, drawable)
                views.setTextViewText(R.id.tvWifiState, label)
            }
            else -> return
        }
        mgr.partiallyUpdateAppWidget(ids, views)
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

        val dev = s["devmode"] == "1"
        val usb = s["usb"] == "1"
        val wifi = s["enabled"] == "1"
        val daemon = s["daemon"] == "1"
        val ip = s["ip"] ?: "--"
        val port = s["port"] ?: "--"
        val ssid = s["ssid"] ?: "--"

        val views = RemoteViews(context.packageName, R.layout.widget)

        // Developer mode (master)
        views.setImageViewResource(
            R.id.ivDevSwitch, if (dev) R.drawable.switch_on else R.drawable.switch_off
        )
        views.setTextViewText(R.id.tvDevState, if (dev) "开启" else "关闭")

        // USB debugging
        views.setImageViewResource(
            R.id.ivUsbSwitch, if (usb) R.drawable.switch_on else R.drawable.switch_off
        )
        views.setTextViewText(R.id.tvUsbState, if (usb) "开启" else "关闭")

        // Wireless ADB
        views.setImageViewResource(
            R.id.ivWifiSwitch, if (wifi) R.drawable.switch_on else R.drawable.switch_off
        )
        views.setTextViewText(R.id.tvWifiState, if (wifi) "开启" else "关闭")

        // Info row
        views.setTextViewText(R.id.tvDaemon, if (daemon) "运行中" else "已停止")
        views.setTextViewText(R.id.tvIp, ip)
        views.setTextViewText(R.id.tvPort, port)
        views.setTextViewText(R.id.tvSsid, ssid)

        // Switch taps: carry the target value (opposite of current) for optimistic UI.
        views.setOnClickPendingIntent(
            R.id.devArea,
            togglePi(context, REQ_DEV, ACTION_DEV, !dev)
        )
        views.setOnClickPendingIntent(
            R.id.usbArea,
            togglePi(context, REQ_USB, ACTION_USB, !usb)
        )
        views.setOnClickPendingIntent(
            R.id.wifiArea,
            togglePi(context, REQ_WIFI, ACTION_WIFI, !wifi)
        )

        val refreshPi = PendingIntent.getBroadcast(
            context, REQ_REFRESH,
            Intent(context, AdbWifiWidget::class.java).apply { action = ACTION_REFRESH },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.infoArea, refreshPi)

        mgr.updateAppWidget(id, views)
    }

    private fun togglePi(context: Context, req: Int, action: String, target: Boolean): PendingIntent =
        PendingIntent.getBroadcast(
            context, req,
            Intent(context, AdbWifiWidget::class.java).apply {
                this.action = action
                putExtra(EXTRA_TARGET, if (target) 1 else 0)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

    private fun ctlPath(context: Context): String =
        File(context.filesDir, ASSET_CTL).absolutePath

    /**
     * Deploy bundled scripts into our private files dir. Redeploy when the
     * bundled version is newer. Failure is non-fatal (status shows "--").
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
