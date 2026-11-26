package net.jilbert.screenrest

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Hosts the Flutter screens and answers their calls over the "screenrest/native" channel. */
class MainActivity : FlutterActivity() {
    companion object {
        const val EXTRA_BREAK = "screenrest_break"
        const val EXTRA_KIND = "screenrest_kind"
        private const val CHANNEL = "screenrest/native"
    }

    private var channel: MethodChannel? = null
    private var launchBreak: Map<String, String>? = null
    private var player: MediaPlayer? = null
    private val prefs by lazy { Prefs(this) }
    private val kinds by lazy { AppKinds(this, prefs) }

    override fun onCreate(savedInstanceState: Bundle?) {
        launchBreak = breakFrom(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        breakFrom(intent)?.let { channel?.invokeMethod("openBreak", it) }
    }

    override fun onDestroy() {
        stopVoice()
        super.onDestroy()
    }

    private fun breakFrom(i: Intent?): Map<String, String>? {
        val type = i?.getStringExtra(EXTRA_BREAK) ?: return null
        val kind = i.getStringExtra(EXTRA_KIND) ?: Kind.OTHER.key
        i.removeExtra(EXTRA_BREAK)
        return mapOf("type" to type, "kind" to kind)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "launchBreak" -> { result.success(launchBreak); launchBreak = null }
                    "getSettings" -> result.success(prefs.settingsMap())
                    "saveSettings" -> {
                        prefs.saveSettings(call.arguments as Map<*, *>)
                        if (BreakService.instance != null) BreakService.start(this, BreakService.ACTION_RELOAD)
                        result.success(null)
                    }
                    "setEnabled" -> {
                        val on = call.arguments as Boolean
                        prefs.enabled = on
                        if (on) BreakService.start(this) else BreakService.stop(this)
                        result.success(null)
                    }
                    "status" -> result.success(status())
                    "stats" -> result.success(Stats(this).days((call.arguments as? Number)?.toInt() ?: 7))
                    "breakDone" -> {
                        val a = call.arguments as Map<*, *>
                        val bt = BreakType.of(a["type"] as? String) ?: BreakType.EYE
                        val taken = a["taken"] as? Boolean ?: true
                        val svc = BreakService.instance
                        if (svc != null) svc.finishBreak(bt, taken) else {
                            val s = Stats(this)
                            s.add("${bt.key}_${if (taken) "taken" else "skipped"}", 1.0)
                            s.flush()
                        }
                        result.success(null)
                    }
                    "pause" -> {
                        val minutes = (call.arguments as Number).toInt()
                        BreakService.start(this, BreakService.ACTION_PAUSE) { putExtra(BreakService.EXTRA_MINUTES, minutes) }
                        result.success(null)
                    }
                    "resume" -> { BreakService.start(this, BreakService.ACTION_RESUME); result.success(null) }
                    "testReminder" -> {
                        val type = call.arguments as? String ?: "eye"
                        BreakService.start(this, BreakService.ACTION_TEST) { putExtra(BreakService.EXTRA_TYPE, type) }
                        result.success(null)
                    }
                    "permissions" -> result.success(permissions())
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                        result.success(null)
                    }
                    "openUsageAccess" -> { open(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)); result.success(null) }
                    "openOverlay" -> {
                        open(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "openBattery" -> { open(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)); result.success(null) }
                    "openDisplay" -> { open(Intent(Settings.ACTION_DISPLAY_SETTINGS)); result.success(null) }
                    "recentApps" -> result.success(kinds.recentApps())
                    "appStats" -> result.success(kinds.appStats(Stats(this), (call.arguments as? Number)?.toInt() ?: 1))
                    "setAppKind" -> {
                        val a = call.arguments as Map<*, *>
                        prefs.setKindOverride(a["pkg"] as String, Kind.of(a["kind"] as? String))
                        result.success(null)
                    }
                    "appIcon" -> {
                        val pkg = call.arguments as String
                        Thread {
                            val png = AppIcons.png(this, pkg)
                            runOnUiThread { result.success(png) }
                        }.start()
                    }
                    "exportPdf" -> {
                        val report = ReportPdf(this, call.arguments as Map<*, *>)
                        Thread {
                            val file = runCatching { report.write() }
                            runOnUiThread {
                                file.fold(
                                    { report.share(it); result.success(true) },
                                    { result.error("pdf", it.message, null) },
                                )
                            }
                        }.start()
                    }
                    "playVoice" -> result.success(playVoice(call.arguments as String))
                    "stopVoice" -> { stopVoice(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }

    private fun status(): Map<String, Any?> {
        BreakService.instance?.let { return it.snapshot() }
        return mapOf("running" to false, "paused_until" to prefs.pausedUntil)
    }

    private fun permissions(): Map<String, Boolean> {
        val notif = Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val pm = getSystemService(android.os.PowerManager::class.java)
        return mapOf(
            "notifications" to notif,
            "usage" to kinds.hasUsageAccess(),
            "overlay" to Settings.canDrawOverlays(this),
            "battery" to pm.isIgnoringBatteryOptimizations(packageName),
        )
    }

    private fun open(i: Intent) {
        try {
            startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /** Plays res/raw/voice_<slug>. Returns false if there is no voice clip for this exercise. */
    private fun playVoice(slug: String): Boolean {
        stopVoice()
        @Suppress("DiscouragedApi")
        val id = resources.getIdentifier("voice_$slug", "raw", packageName)
        if (id == 0) return false
        player = MediaPlayer.create(this, id)?.apply {
            setOnCompletionListener { stopVoice() }
            start()
        }
        return player != null
    }

    private fun stopVoice() {
        player?.runCatching { stop(); release() }
        player = null
    }
}
