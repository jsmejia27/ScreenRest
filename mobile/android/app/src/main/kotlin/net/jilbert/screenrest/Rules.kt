package net.jilbert.screenrest

import kotlin.math.max
import kotlin.math.min

/** What the person is doing on the phone. Decides how long until the next break and what the break contains. */
enum class Kind {
    READING, WATCHING, GAMING, OTHER;

    val key: String get() = name.lowercase()

    companion object {
        fun of(s: String?): Kind? = entries.firstOrNull { it.key == s }
    }
}

/** EYE = 20-second look-away. BODY = 1-2 minute break: hands for gamers, neck and shoulders for everyone else. */
enum class BreakType {
    EYE, BODY;

    val key: String get() = name.lowercase()

    companion object {
        fun of(s: String?): BreakType? = entries.firstOrNull { it.key == s }
    }
}

data class RuleConfig(
    /** Minutes of screen time before an eye break, per activity. */
    val eyeMin: Map<Kind, Int> = mapOf(Kind.READING to 20, Kind.WATCHING to 30, Kind.GAMING to 40, Kind.OTHER to 20),
    /** Minutes of screen time before a body break (any activity). */
    val bodyMin: Int = 60,
    /** Screen off this long counts as an eye rest. */
    val eyeRestSec: Int = 5 * 60,
    /** Screen off this long counts as a full rest. */
    val bodyRestSec: Int = 15 * 60,
    /** "Later" and ignored reminders come back after this long. */
    val snoozeSec: Int = 10 * 60,
    /** After this many snoozes (or ignored reminders) the reminder becomes firm. */
    val maxSnoozes: Int = 2,
    /** While a video plays, wait this long for it to pause before reminding anyway. */
    val maxWaitForPauseSec: Int = 10 * 60,
) {
    fun eyeMinutes(kind: Kind): Int = max(1, eyeMin[kind] ?: 20)
}

enum class Prompt {
    /** Nothing due. */
    NONE,
    /** A break is due but this is a bad moment (call, video playing, snoozed). */
    WAIT,
    /** A reminder was already shown and is still waiting for the person. */
    SHOWN,
    /** Show a gentle reminder now. */
    NUDGE,
    /** Show a firm reminder now (after repeated snoozes). */
    FIRM,
}

data class Decision(val prompt: Prompt, val type: BreakType? = null)

/**
 * Break timing, free of Android types so it can be unit tested.
 *
 * Screen-on time fills two "loads" from 0 to 1. The eye load fills faster or slower depending on
 * the activity (20 min reading, 30 min watching, 40 min gaming), so switching apps mid-way works
 * naturally. Putting the phone down for a while empties the loads.
 */
class BreakRules(var config: RuleConfig = RuleConfig()) {
    var eyeLoad = 0.0
    var bodyLoad = 0.0
    var pending: BreakType? = null
    var pendingSince = 0L
    var notified = false
    var lastPromptAt = 0L
    var snoozes = 0
    var snoozedUntil = 0L
    /** When the screen went off, or 0 while it is on. */
    var offSince = 0L
    /** Start of the current stretch of use without a rest or break. */
    var sessionStart = 0L

    fun screenOff(now: Long) {
        if (offSince == 0L) offSince = now
    }

    /** Screen turned on and unlocked. Returns true when the time away counted as a rest. */
    fun screenOn(now: Long): Boolean {
        val off = offSince
        offSince = 0L
        var rested = false
        if (off > 0L) {
            val restSec = (now - off) / 1000
            if (restSec >= config.eyeRestSec) {
                eyeLoad = 0.0
                rested = true
            }
            if (restSec >= config.bodyRestSec) bodyLoad = 0.0
        }
        if (rested || sessionStart == 0L) sessionStart = now
        if (rested) clearPending()
        return rested
    }

    fun tick(now: Long, dtSec: Double, kind: Kind, mediaPlaying: Boolean, inCall: Boolean): Decision {
        if (dtSec > 0) {
            eyeLoad += dtSec / (config.eyeMinutes(kind) * 60.0)
            bodyLoad += dtSec / (max(1, config.bodyMin) * 60.0)
        }
        val due = when {
            bodyLoad >= 1.0 -> BreakType.BODY
            eyeLoad >= 1.0 -> BreakType.EYE
            else -> null
        }
        if (due == null) {
            clearPending()
            return Decision(Prompt.NONE)
        }
        if (pending == null) pendingSince = now
        if (pending != due) {
            pending = due
            notified = false
        }
        if (inCall) return Decision(Prompt.WAIT, due)
        if (now < snoozedUntil) return Decision(Prompt.WAIT, due)
        val waitingForPause = kind == Kind.WATCHING && mediaPlaying &&
            now - pendingSince < config.maxWaitForPauseSec * 1000L
        if (waitingForPause && !notified) return Decision(Prompt.WAIT, due)
        if (notified) {
            // An ignored reminder counts as a snooze, so it comes back and eventually gets firm.
            if (now - lastPromptAt < config.snoozeSec * 1000L) return Decision(Prompt.SHOWN, due)
            snoozes++
        }
        notified = true
        lastPromptAt = now
        return Decision(if (snoozes >= config.maxSnoozes) Prompt.FIRM else Prompt.NUDGE, due)
    }

    /** "Later": come back in a few minutes. */
    fun snooze(now: Long) {
        snoozes++
        snoozedUntil = now + config.snoozeSec * 1000L
        notified = false
    }

    /** The break was taken or skipped. Either way the timer starts over. */
    fun finish(type: BreakType, now: Long) {
        eyeLoad = 0.0
        if (type == BreakType.BODY) bodyLoad = 0.0
        sessionStart = now
        clearPending()
    }

    fun clearPending() {
        pending = null
        pendingSince = 0L
        notified = false
        lastPromptAt = 0L
        snoozes = 0
        snoozedUntil = 0L
    }

    fun secondsToEye(kind: Kind): Int = max(0.0, (1.0 - eyeLoad) * config.eyeMinutes(kind) * 60).toInt()
    fun secondsToBody(): Int = max(0.0, (1.0 - bodyLoad) * max(1, config.bodyMin) * 60).toInt()
    fun secondsToNext(kind: Kind): Int = min(secondsToEye(kind), secondsToBody())
    fun nextType(kind: Kind): BreakType = if (secondsToBody() <= secondsToEye(kind)) BreakType.BODY else BreakType.EYE
    fun sessionSec(now: Long): Long = if (sessionStart == 0L || offSince != 0L) 0L else max(0L, (now - sessionStart) / 1000)
}

/** Late-night and dark-room tips. Each fires at most once per cooldown. */
class Tips {
    var lateSec = 0.0
    var lastLateTip = 0L
    var darkSince = 0L
    var lastDarkTip = 0L

    enum class Tip { LATE_NIGHT, DARK_ROOM }

    companion object {
        const val LATE_FIRST_SEC = 5 * 60
        const val LATE_COOLDOWN_MS = 30 * 60_000L
        const val DARK_LUX = 8f
        const val DARK_AFTER_MS = 3 * 60_000L
        const val DARK_COOLDOWN_MS = 60 * 60_000L

        /** True when minute-of-day m falls in [start, end), wrapping past midnight. */
        fun inWindow(m: Int, start: Int, end: Int): Boolean =
            if (start == end) false else if (start < end) m in start until end else m >= start || m < end
    }

    /**
     * @param lux ambient light, or a negative value when the phone has no light sensor.
     * @param lateNow true when the clock is inside the bedtime window and bedtime tips are on.
     */
    fun tick(now: Long, dtSec: Double, lateNow: Boolean, lux: Float, darkTipsOn: Boolean): Tip? {
        if (lateNow) {
            lateSec += dtSec
            val ready = if (lastLateTip == 0L) lateSec >= LATE_FIRST_SEC else now - lastLateTip >= LATE_COOLDOWN_MS
            if (ready) {
                lastLateTip = now
                return Tip.LATE_NIGHT
            }
        } else {
            lateSec = 0.0
            lastLateTip = 0L
        }
        if (darkTipsOn && lux in 0f..DARK_LUX) {
            if (darkSince == 0L) darkSince = now
            if (now - darkSince >= DARK_AFTER_MS && (lastDarkTip == 0L || now - lastDarkTip >= DARK_COOLDOWN_MS)) {
                lastDarkTip = now
                return Tip.DARK_ROOM
            }
        } else {
            darkSince = 0L
        }
        return null
    }

    fun isDark(now: Long): Boolean = darkSince != 0L && now - darkSince >= 60_000L
}
