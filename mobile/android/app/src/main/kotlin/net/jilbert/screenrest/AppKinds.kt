package net.jilbert.screenrest

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process

/** Works out whether an app is for reading, watching or gaming, and which app is on screen. */
class AppKinds(private val context: Context, private val prefs: Prefs) {
    private val pm: PackageManager = context.packageManager
    private val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    private val cache = HashMap<String, Kind>()
    private var lastQuery = 0L
    var foreground: String? = null
        private set

    companion object {
        /** Popular apps in the Philippines whose store category is missing or misleading. */
        val KNOWN: Map<String, Kind> = mapOf(
            // Gaming
            "com.mobile.legends" to Kind.GAMING,
            "com.activision.callofduty.shooter" to Kind.GAMING,
            "com.garena.game.codm" to Kind.GAMING,
            "com.roblox.client" to Kind.GAMING,
            "com.miHoYo.GenshinImpact" to Kind.GAMING,
            "com.HoYoverse.hkrpgoversea" to Kind.GAMING,
            "com.tencent.ig" to Kind.GAMING,
            "com.dts.freefireth" to Kind.GAMING,
            "com.dts.freefiremax" to Kind.GAMING,
            "com.supercell.clashofclans" to Kind.GAMING,
            "com.supercell.clashroyale" to Kind.GAMING,
            "com.supercell.brawlstars" to Kind.GAMING,
            "com.levelinfinite.sgameGlobal" to Kind.GAMING,
            "com.mojang.minecraftpe" to Kind.GAMING,
            // Watching
            "com.google.android.youtube" to Kind.WATCHING,
            "com.netflix.mediaclient" to Kind.WATCHING,
            "com.disney.disneyplus" to Kind.WATCHING,
            "com.amazon.avod.thirdpartyclient" to Kind.WATCHING,
            "com.vuclip.viu" to Kind.WATCHING,
            "tv.twitch.android.app" to Kind.WATCHING,
            "com.bilibili.app.in" to Kind.WATCHING,
            // Reading and scrolling
            "com.facebook.katana" to Kind.READING,
            "com.facebook.lite" to Kind.READING,
            "com.facebook.orca" to Kind.READING,
            "com.facebook.mlite" to Kind.READING,
            "com.instagram.android" to Kind.READING,
            "com.zhiliaoapp.musically" to Kind.READING,
            "com.ss.android.ugc.trill" to Kind.READING,
            "com.twitter.android" to Kind.READING,
            "com.reddit.frontpage" to Kind.READING,
            "com.threads.android" to Kind.READING,
            "wp.wattpad" to Kind.READING,
            "com.naver.linewebtoon" to Kind.READING,
            "com.android.chrome" to Kind.READING,
            "com.shopee.ph" to Kind.READING,
            "com.lazada.android" to Kind.READING,
            "com.google.android.apps.magazines" to Kind.READING,
            "com.google.android.apps.books" to Kind.READING,
            "com.amazon.kindle" to Kind.READING,
        )
    }

    fun hasUsageAccess(): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            @Suppress("DEPRECATION")
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Category from the app itself or the built-in list, ignoring the person's own labels. */
    fun autoKind(pkg: String): Kind {
        cache[pkg]?.let { return it }
        val k = KNOWN[pkg] ?: try {
            val ai = pm.getApplicationInfo(pkg, 0)
            @Suppress("DEPRECATION")
            when {
                ai.category == ApplicationInfo.CATEGORY_GAME || (ai.flags and ApplicationInfo.FLAG_IS_GAME) != 0 -> Kind.GAMING
                ai.category == ApplicationInfo.CATEGORY_VIDEO -> Kind.WATCHING
                ai.category == ApplicationInfo.CATEGORY_SOCIAL ||
                    ai.category == ApplicationInfo.CATEGORY_NEWS ||
                    ai.category == ApplicationInfo.CATEGORY_IMAGE -> Kind.READING
                else -> Kind.OTHER
            }
        } catch (_: PackageManager.NameNotFoundException) {
            Kind.OTHER
        }
        cache[pkg] = k
        return k
    }

    fun kindOf(pkg: String?): Kind {
        if (pkg == null || pkg == context.packageName) return Kind.OTHER
        return prefs.kindOverride(pkg) ?: autoKind(pkg)
    }

    /** Reads new app-switch events since the last call and returns the app now on screen. */
    fun updateForeground(now: Long): String? {
        if (!hasUsageAccess()) {
            foreground = null
            return null
        }
        val from = if (lastQuery == 0L || now - lastQuery > 3_600_000L) now - 10 * 60_000L else lastQuery
        try {
            val events = usm.queryEvents(from, now)
            val e = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(e)
                // 1 = ACTIVITY_RESUMED (API 29+), same value as the older MOVE_TO_FOREGROUND.
                if (e.eventType == 1) foreground = e.packageName
            }
        } catch (_: SecurityException) {
            // Usage access was turned off while running.
        }
        lastQuery = now
        return foreground
    }

    fun label(pkg: String): String = try {
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        pkg
    }

    /** Apps used in the last 7 days (most used first) with their activity type, for the "Your apps" screen. */
    fun recentApps(): List<Map<String, Any>> {
        if (!hasUsageAccess()) return emptyList()
        val now = System.currentTimeMillis()
        val totals = HashMap<String, Long>()
        try {
            for (s in usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, now - 7 * 86_400_000L, now)) {
                totals[s.packageName] = (totals[s.packageName] ?: 0L) + s.totalTimeInForeground
            }
        } catch (_: SecurityException) {
            return emptyList()
        }
        val launchable = pm.queryIntentActivities(
            android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_LAUNCHER), 0,
        ).map { it.activityInfo.packageName }.toSet()
        return totals.entries
            .filter { it.value >= 60_000L && it.key != context.packageName && it.key in launchable }
            .sortedByDescending { it.value }
            .take(60)
            .map { (pkg, ms) ->
                val override = prefs.kindOverride(pkg)
                mapOf(
                    "pkg" to pkg,
                    "label" to label(pkg),
                    "kind" to (override ?: autoKind(pkg)).key,
                    "custom" to (override != null),
                    "minutes" to (ms / 60_000L).toInt(),
                )
            }
    }

    /**
     * Screen time per app over the last [days] days, as counted by ScreenRest itself (screen on and
     * unlocked only), most used first. Leaves out the home screen and system pop-ups, which aren't apps
     * anyone "uses", and anything under 30 seconds.
     */
    fun appStats(stats: Stats, days: Int): List<Map<String, Any>> {
        val launchable = pm.queryIntentActivities(
            android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_LAUNCHER), 0,
        ).map { it.activityInfo.packageName }.toSet()
        val home = pm.queryIntentActivities(
            android.content.Intent(android.content.Intent.ACTION_MAIN).addCategory(android.content.Intent.CATEGORY_HOME), 0,
        ).map { it.activityInfo.packageName }.toSet()
        return stats.appTotals(days).entries
            .filter { (pkg, t) -> t.first >= 30 && pkg in launchable && pkg !in home && pkg != context.packageName }
            .sortedByDescending { it.value.first }
            .take(30)
            .map { (pkg, t) ->
                mapOf("pkg" to pkg, "label" to label(pkg), "kind" to kindOf(pkg).key, "seconds" to t.first, "late" to t.second)
            }
    }
}
