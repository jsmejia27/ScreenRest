package net.jilbert.screenrest

import android.content.Context
import org.json.JSONObject
import java.time.LocalDate

/**
 * Daily totals kept on the phone only, one JSON object per day (key "2026-11-26").
 * Seconds per activity, breaks taken/skipped, snoozes, longest session, late-night and dark-room seconds.
 */
class Stats(context: Context) {
    private val sp = context.getSharedPreferences("screenrest_stats", Context.MODE_PRIVATE)
    private var day: String = ""
    private var cur = JSONObject()
    private var dirty = false

    companion object {
        val FIELDS = listOf(
            "reading", "watching", "gaming", "other",
            "eye_taken", "eye_skipped", "body_taken", "body_skipped", "snoozes",
            "longest", "late", "dark",
        )
        const val KEEP_DAYS = 60L
    }

    private fun today(): JSONObject {
        val d = LocalDate.now().toString()
        if (d != day) {
            flush()
            day = d
            cur = sp.getString(d, null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
            prune()
        }
        return cur
    }

    private var lastFlush = 0L

    fun add(field: String, n: Double) {
        val o = today()
        o.put(field, o.optDouble(field, 0.0) + n)
        dirty = true
        // Save at least once a minute so the home screen and a crash don't lose the numbers.
        val now = System.currentTimeMillis()
        if (now - lastFlush >= 60_000L) flush()
    }

    /** Screen time for one app, kept per day as {"apps": {pkg: seconds}, "apps_late": {pkg: seconds}}. */
    fun addApp(pkg: String, sec: Double, late: Boolean) {
        val o = today()
        for (key in if (late) listOf("apps", "apps_late") else listOf("apps")) {
            val m = o.optJSONObject(key) ?: JSONObject().also { o.put(key, it) }
            m.put(pkg, m.optDouble(pkg, 0.0) + sec)
        }
        dirty = true
    }

    /** Per-app totals over the last [n] days: pkg -> (seconds, late-night seconds). */
    fun appTotals(n: Int): Map<String, Pair<Double, Double>> {
        today()
        flush()
        val end = LocalDate.now()
        val out = HashMap<String, Pair<Double, Double>>()
        for (back in 0 until n) {
            val o = sp.getString(end.minusDays(back.toLong()).toString(), null)
                ?.let { runCatching { JSONObject(it) }.getOrNull() } ?: continue
            val apps = o.optJSONObject("apps") ?: continue
            val late = o.optJSONObject("apps_late")
            for (pkg in apps.keys()) {
                val (s, l) = out[pkg] ?: (0.0 to 0.0)
                out[pkg] = (s + apps.optDouble(pkg, 0.0)) to (l + (late?.optDouble(pkg, 0.0) ?: 0.0))
            }
        }
        return out
    }

    fun max(field: String, v: Double) {
        val o = today()
        if (v > o.optDouble(field, 0.0)) {
            o.put(field, v)
            dirty = true
        }
    }

    fun flush() {
        if (dirty && day.isNotEmpty()) {
            sp.edit().putString(day, cur.toString()).apply()
            dirty = false
        }
        lastFlush = System.currentTimeMillis()
    }

    /** The last [n] days, oldest first, each as {date, field: number...}. */
    fun days(n: Int): List<Map<String, Any>> {
        today()
        flush()
        val end = LocalDate.now()
        return (n - 1 downTo 0).map { back ->
            val d = end.minusDays(back.toLong()).toString()
            val o = sp.getString(d, null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
            val m = mutableMapOf<String, Any>("date" to d)
            for (f in FIELDS) m[f] = o.optDouble(f, 0.0)
            m
        }
    }

    private fun prune() {
        val cutoff = LocalDate.now().minusDays(KEEP_DAYS).toString()
        val old = sp.all.keys.filter { it < cutoff }
        if (old.isNotEmpty()) sp.edit().apply { old.forEach { remove(it) } }.apply()
    }
}
