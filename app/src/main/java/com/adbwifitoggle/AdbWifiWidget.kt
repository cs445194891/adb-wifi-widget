package com.adbwifitoggle

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.util.concurrent.TimeUnit

/**
 * Home-screen widget for controlling wireless ADB (ADB over TLS) on a rooted device.
 *
 * Root is obtained through Magisk su by invoking the device-side script:
 *   /data/adb/adb_wifi_ctl.sh {toggle|status}
 *
 * No foreground service: state is refreshed only when the user taps the widget
 * or when the system delivers an APPWIDGET_UPDATE. updatePeriodMillis is 0 in
 * widget_info.xml, so in practice refresh is tap-driven.
 *
 * All su calls run off the main thread via goAsync() to avoid ANR.
 */
class AdbWifiWidget : AppWidgetProvider() {

    companion object {
        private const val ACTION_TOGGLE = "com.adbwifitoggle.TOGGLE"
        private const val ACTION_REFRESH = "com.adbwifitoggle.REFRESH"
        private const val CTL = "/data/adb/adb_wifi_ctl.sh"

        private const val REQ_TOGGLE = 1
        private const val REQ_REFRESH = 2
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // onUpdate is dispatched synchronously from onReceive; goAsync() is
        // still valid here because onReceive has not returned yet.
        val result = goAsync()
        Thread {
            try {
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
                        if (intent.action == ACTION_TOGGLE) runRoot("$CTL toggle")
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
        val raw = runRoot("$CTL status")
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
            if (daemon) "守护·运行" else "守护·停止"
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
