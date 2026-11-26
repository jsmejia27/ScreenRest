package net.jilbert.screenrest

import android.content.Context
import android.content.SharedPreferences
import java.util.Locale

/** Settings shared by the Flutter screens and the background service, plus the saved break state. */
class Prefs(context: Context) {
    val sp: SharedPreferences = context.getSharedPreferences("screenrest", Context.MODE_PRIVATE)

    var lang: String
        get() = sp.getString("lang", null) ?: defaultLang()
        set(v) = sp.edit().putString("lang", v).apply()
    val tl: Boolean get() = lang == "tl"

    var enabled: Boolean
        get() = sp.getBoolean("enabled", false)
        set(v) = sp.edit().putBoolean("enabled", v).apply()

    var pausedUntil: Long
        get() = sp.getLong("paused_until", 0L)
        set(v) = sp.edit().putLong("paused_until", v).apply()

    val sound: String get() = sp.getString("sound", "voice") ?: "voice"
    val fullScreen: Boolean get() = sp.getBoolean("full_screen", false)
    val bedtimeOn: Boolean get() = sp.getBoolean("bedtime_on", true)
    val bedtimeStart: Int get() = sp.getInt("bedtime_start", 23 * 60)
    val bedtimeEnd: Int get() = sp.getInt("bedtime_end", 6 * 60)
    val darkTips: Boolean get() = sp.getBoolean("dark_tips", true)

    fun ruleConfig(): RuleConfig = RuleConfig(
        eyeMin = mapOf(
            Kind.READING to sp.getInt("eye_reading", 20),
            Kind.WATCHING to sp.getInt("eye_watching", 30),
            Kind.GAMING to sp.getInt("eye_gaming", 40),
            Kind.OTHER to sp.getInt("eye_other", 20),
        ),
        bodyMin = sp.getInt("body_min", 60),
    )

    /** Settings as a map for Flutter. */
    fun settingsMap(): Map<String, Any> = mapOf(
        "lang" to lang,
        "enabled" to enabled,
        "eye_reading" to sp.getInt("eye_reading", 20),
        "eye_watching" to sp.getInt("eye_watching", 30),
        "eye_gaming" to sp.getInt("eye_gaming", 40),
        "eye_other" to sp.getInt("eye_other", 20),
        "body_min" to sp.getInt("body_min", 60),
        "sound" to sound,
        "full_screen" to fullScreen,
        "bedtime_on" to bedtimeOn,
        "bedtime_start" to bedtimeStart,
        "bedtime_end" to bedtimeEnd,
        "dark_tips" to darkTips,
        "onboarded" to sp.getBoolean("onboarded", false),
        "paused_until" to pausedUntil,
    )

    /** Saves the settings Flutter sends. Unknown keys and wrong types are ignored. */
    fun saveSettings(m: Map<*, *>) {
        val e = sp.edit()
        for ((k, v) in m) {
            val key = k as? String ?: continue
            when (key) {
                "lang", "sound" -> (v as? String)?.let { e.putString(key, it) }
                "enabled", "full_screen", "bedtime_on", "dark_tips", "onboarded" -> (v as? Boolean)?.let { e.putBoolean(key, it) }
                "eye_reading", "eye_watching", "eye_gaming", "eye_other", "body_min", "bedtime_start", "bedtime_end" ->
                    (v as? Number)?.let { e.putInt(key, it.toInt()) }
                "paused_until" -> (v as? Number)?.let { e.putLong(key, it.toLong()) }
            }
        }
        e.apply()
    }

    fun kindOverride(pkg: String): Kind? = Kind.of(sp.getString("kind_$pkg", null))

    fun setKindOverride(pkg: String, kind: Kind?) {
        val e = sp.edit()
        if (kind == null) e.remove("kind_$pkg") else e.putString("kind_$pkg", kind.key)
        e.apply()
    }

    fun saveRules(r: BreakRules) {
        sp.edit()
            .putFloat("r_eye", r.eyeLoad.toFloat())
            .putFloat("r_body", r.bodyLoad.toFloat())
            .putString("r_pending", r.pending?.key)
            .putLong("r_since", r.pendingSince)
            .putBoolean("r_notified", r.notified)
            .putLong("r_prompt_at", r.lastPromptAt)
            .putInt("r_snoozes", r.snoozes)
            .putLong("r_snoozed_until", r.snoozedUntil)
            .putLong("r_off", r.offSince)
            .putLong("r_session", r.sessionStart)
            .apply()
    }

    fun loadRules(r: BreakRules) {
        r.eyeLoad = sp.getFloat("r_eye", 0f).toDouble()
        r.bodyLoad = sp.getFloat("r_body", 0f).toDouble()
        r.pending = BreakType.of(sp.getString("r_pending", null))
        r.pendingSince = sp.getLong("r_since", 0L)
        r.notified = sp.getBoolean("r_notified", false)
        r.lastPromptAt = sp.getLong("r_prompt_at", 0L)
        r.snoozes = sp.getInt("r_snoozes", 0)
        r.snoozedUntil = sp.getLong("r_snoozed_until", 0L)
        r.offSince = sp.getLong("r_off", 0L)
        r.sessionStart = sp.getLong("r_session", 0L)
    }

    /** English or Tagalog text, for notifications built in Kotlin. */
    fun t(en: String, tl: String): String = if (this.tl) tl else en

    companion object {
        fun defaultLang(): String {
            val l = Locale.getDefault().language
            return if (l == "fil" || l == "tl") "tl" else "en"
        }
    }
}
