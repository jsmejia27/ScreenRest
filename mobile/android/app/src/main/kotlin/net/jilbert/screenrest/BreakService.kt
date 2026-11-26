package net.jilbert.screenrest

import android.app.KeyguardManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import java.text.DateFormat
import java.util.Calendar
import java.util.Date

/**
 * Runs while protection is on. Counts screen-on, unlocked time, checks which kind of app is open,
 * and reminds the person to rest at a good moment. Ticks only while the screen is on.
 */
class BreakService : Service() {
    companion object {
        const val ACTION_SNOOZE = "net.jilbert.screenrest.SNOOZE"
        const val ACTION_SKIP = "net.jilbert.screenrest.SKIP"
        const val ACTION_DONE = "net.jilbert.screenrest.DONE"
        const val ACTION_PAUSE = "net.jilbert.screenrest.PAUSE"
        const val ACTION_RESUME = "net.jilbert.screenrest.RESUME"
        const val ACTION_RELOAD = "net.jilbert.screenrest.RELOAD"
        const val ACTION_TEST = "net.jilbert.screenrest.TEST"
        const val EXTRA_TYPE = "type"
        const val EXTRA_TAKEN = "taken"
        const val EXTRA_MINUTES = "minutes"
        private const val TICK_MS = 15_000L

        @Volatile var instance: BreakService? = null
            private set

        fun start(ctx: Context, action: String? = null, extras: Intent.() -> Unit = {}) {
            val i = Intent(ctx, BreakService::class.java)
            if (action != null) i.action = action
            i.extras()
            ctx.startForegroundService(i)
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, BreakService::class.java))
        }
    }

    private lateinit var prefs: Prefs
    private lateinit var stats: Stats
    private lateinit var kinds: AppKinds
    private lateinit var notifier: Notifier
    private val rules = BreakRules()
    private val tips = Tips()
    private val handler = Handler(Looper.getMainLooper())
    private var ticking = false
    private var lastTick = 0L
    private var lastStatusText = ""
    private var lastStatusAt = 0L
    private var lux = -1f
    private var lightRegistered = false
    var currentKind: Kind = Kind.OTHER
        private set
    var mediaPlaying = false
        private set
    var inCall = false
        private set

    private val sensors by lazy { getSystemService(SensorManager::class.java) }
    private val audio by lazy { getSystemService(AudioManager::class.java) }
    private val power by lazy { getSystemService(PowerManager::class.java) }
    private val keyguard by lazy { getSystemService(KeyguardManager::class.java) }

    private val tickRunnable = object : Runnable {
        override fun run() {
            tick()
            if (ticking) handler.postDelayed(this, TICK_MS)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            when (i.action) {
                Intent.ACTION_SCREEN_OFF -> onInactive()
                Intent.ACTION_USER_PRESENT -> onActive()
                Intent.ACTION_SCREEN_ON -> if (!keyguard.isKeyguardLocked) onActive()
            }
        }
    }

    private val lightListener = object : SensorEventListener {
        override fun onSensorChanged(e: SensorEvent) { lux = e.values[0] }
        override fun onAccuracyChanged(s: Sensor?, a: Int) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        stats = Stats(this)
        kinds = AppKinds(this, prefs)
        notifier = Notifier(this, prefs)
        notifier.createChannels()
        rules.config = prefs.ruleConfig()
        prefs.loadRules(rules)
        val n = notifier.status(statusText(), isPaused())
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(Notifier.ID_STATUS, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(Notifier.ID_STATUS, n)
        }
        val f = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        registerReceiver(screenReceiver, f)
        instance = this
        if (power.isInteractive && !keyguard.isKeyguardLocked) onActive() else onInactive()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val now = System.currentTimeMillis()
        when (intent?.action) {
            ACTION_SNOOZE -> {
                rules.snooze(now)
                stats.add("snoozes", 1.0)
                notifier.cancelBreak()
            }
            ACTION_SKIP, ACTION_DONE -> {
                val type = BreakType.of(intent.getStringExtra(EXTRA_TYPE)) ?: rules.pending ?: BreakType.EYE
                val taken = intent.action == ACTION_DONE && intent.getBooleanExtra(EXTRA_TAKEN, true)
                finishBreak(type, taken, now)
            }
            ACTION_PAUSE -> prefs.pausedUntil = now + intent.getIntExtra(EXTRA_MINUTES, 60) * 60_000L
            ACTION_RESUME -> prefs.pausedUntil = 0L
            ACTION_RELOAD -> rules.config = prefs.ruleConfig()
            ACTION_TEST -> notifier.showBreak(BreakType.of(intent.getStringExtra(EXTRA_TYPE)) ?: BreakType.EYE, currentKind, false)
        }
        prefs.saveRules(rules)
        updateStatus(force = true)
        return START_STICKY
    }

    override fun onDestroy() {
        instance = null
        ticking = false
        handler.removeCallbacks(tickRunnable)
        runCatching { unregisterReceiver(screenReceiver) }
        unregisterLight()
        rules.screenOff(System.currentTimeMillis())
        prefs.saveRules(rules)
        stats.flush()
        super.onDestroy()
    }

    fun finishBreak(type: BreakType, taken: Boolean, now: Long = System.currentTimeMillis()) {
        rules.finish(type, now)
        stats.add("${type.key}_${if (taken) "taken" else "skipped"}", 1.0)
        stats.flush()
        notifier.cancelBreak()
        prefs.saveRules(rules)
        updateStatus(force = true)
    }

    private fun isPaused(): Boolean = prefs.pausedUntil > System.currentTimeMillis()

    private fun onActive() {
        val now = System.currentTimeMillis()
        rules.screenOn(now)
        lastTick = now
        registerLight()
        if (!ticking) {
            ticking = true
            handler.postDelayed(tickRunnable, TICK_MS)
        }
        updateStatus(force = true)
    }

    private fun onInactive() {
        val now = System.currentTimeMillis()
        if (ticking) tick() // count the last partial interval
        ticking = false
        handler.removeCallbacks(tickRunnable)
        unregisterLight()
        rules.screenOff(now)
        prefs.saveRules(rules)
        stats.flush()
    }

    private fun registerLight() {
        if (lightRegistered) return
        val s = sensors.getDefaultSensor(Sensor.TYPE_LIGHT) ?: return
        lightRegistered = sensors.registerListener(lightListener, s, SensorManager.SENSOR_DELAY_NORMAL)
    }

    private fun unregisterLight() {
        if (lightRegistered) sensors.unregisterListener(lightListener)
        lightRegistered = false
        lux = -1f
    }

    private fun minuteOfDay(): Int = Calendar.getInstance().let { it.get(Calendar.HOUR_OF_DAY) * 60 + it.get(Calendar.MINUTE) }

    private fun tick() {
        val now = System.currentTimeMillis()
        val dt = ((now - lastTick) / 1000.0).coerceIn(0.0, 60.0)
        lastTick = now
        if (!power.isInteractive || keyguard.isKeyguardLocked) return

        val pkg = kinds.updateForeground(now)
        mediaPlaying = audio.isMusicActive
        inCall = audio.mode == AudioManager.MODE_IN_CALL || audio.mode == AudioManager.MODE_IN_COMMUNICATION
        var kind = kinds.kindOf(pkg)
        // Unknown app playing audio, e.g. a video in the browser.
        if (kind == Kind.OTHER && mediaPlaying && pkg != null && pkg != packageName) kind = Kind.WATCHING
        currentKind = kind

        if (pkg == packageName) {
            // Looking at ScreenRest itself (a break, or the stats): not screen time, and no break timers.
            stats.flush() // so "Your week" includes the minute just before opening ScreenRest
            updateStatus()
            return
        }

        val late = prefs.bedtimeOn && Tips.inWindow(minuteOfDay(), prefs.bedtimeStart, prefs.bedtimeEnd)
        stats.add(kind.key, dt)
        if (late) stats.add("late", dt)
        if (pkg != null) stats.addApp(pkg, dt, late)

        if (isPaused()) {
            updateStatus()
            return
        }

        val d = rules.tick(now, dt, kind, mediaPlaying, inCall)
        when (d.prompt) {
            Prompt.NUDGE -> notifier.showBreak(d.type!!, kind, firm = false)
            Prompt.FIRM -> {
                notifier.showBreak(d.type!!, kind, firm = true)
                if (prefs.fullScreen && Settings.canDrawOverlays(this)) openBreakScreen(d.type, kind)
            }
            Prompt.NONE -> notifier.cancelBreak()
            else -> {}
        }
        stats.max("longest", rules.sessionSec(now).toDouble())

        tips.tick(now, dt, late, lux, prefs.darkTips)?.let { notifier.showTip(it) }
        if (tips.isDark(now)) stats.add("dark", dt)

        prefs.saveRules(rules)
        updateStatus()
    }

    private fun openBreakScreen(type: BreakType, kind: Kind) {
        val i = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(MainActivity.EXTRA_BREAK, type.key)
            .putExtra(MainActivity.EXTRA_KIND, kind.key)
        runCatching { startActivity(i) }
    }

    private fun statusText(): String {
        val t = prefs::t
        if (isPaused()) {
            val until = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(prefs.pausedUntil))
            return t("Breaks paused until $until", "Naka-pause ang break hanggang $until")
        }
        val kindName = notifier.kindName(currentKind)
        if (rules.pending != null) {
            return when {
                inCall -> t("Break waiting until your call ends", "Naghihintay ang break hanggang matapos ang tawag")
                currentKind == Kind.WATCHING && mediaPlaying -> t("Break waiting for your video to pause", "Naghihintay ang break na i-pause mo ang video")
                else -> t("A break is due", "Oras na ng break")
            }
        }
        val min = (rules.secondsToNext(currentKind) + 59) / 60
        val what = if (rules.nextType(currentKind) == BreakType.BODY) t("stretch break", "pag-unat") else t("eye break", "break ng mata")
        return t("Next $what in $min min · $kindName", "Susunod na $what sa loob ng $min min · $kindName")
    }

    private fun updateStatus(force: Boolean = false) {
        val now = System.currentTimeMillis()
        val text = statusText()
        if (!force && text == lastStatusText && now - lastStatusAt < 60_000L) return
        lastStatusText = text
        lastStatusAt = now
        notifier.showStatus(text, isPaused())
    }

    /** Live state for the home screen. */
    fun snapshot(): Map<String, Any?> {
        val now = System.currentTimeMillis()
        return mapOf(
            "running" to true,
            "kind" to currentKind.key,
            "app" to kinds.foreground?.let { if (it == packageName) null else kinds.label(it) },
            "eye_in" to rules.secondsToEye(currentKind),
            "body_in" to rules.secondsToBody(),
            "pending" to rules.pending?.key,
            "session" to rules.sessionSec(now),
            "paused_until" to prefs.pausedUntil,
            "media" to mediaPlaying,
            "call" to inCall,
            "status" to statusText(),
        )
    }
}
