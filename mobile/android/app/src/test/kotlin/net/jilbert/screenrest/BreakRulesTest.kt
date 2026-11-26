package net.jilbert.screenrest

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BreakRulesTest {
    private val step = 15.0 // seconds per tick, same as the service

    /** Ticks until the first prompt that needs showing; returns minutes elapsed and the decision. */
    private fun runUntilPrompt(
        r: BreakRules, start: Long, maxMin: Int, kind: Kind,
        media: (Long) -> Boolean = { false }, call: Boolean = false,
    ): Pair<Double, Decision>? {
        var now = start
        val end = start + maxMin * 60_000L
        while (now < end) {
            now += (step * 1000).toLong()
            val d = r.tick(now, step, kind, media(now), call)
            if (d.prompt == Prompt.NUDGE || d.prompt == Prompt.FIRM) return (now - start) / 60_000.0 to d
        }
        return null
    }

    private fun fresh(start: Long = 1_000_000L) = BreakRules().also { it.screenOn(start) }

    @Test fun readingEyeBreakAfter20Minutes() {
        val (min, d) = runUntilPrompt(fresh(), 1_000_000L, 120, Kind.READING)!!
        assertEquals(20.0, min, 0.26)
        assertEquals(Decision(Prompt.NUDGE, BreakType.EYE), d)
    }

    @Test fun gamingEyeBreakAfter40Minutes() {
        val (min, d) = runUntilPrompt(fresh(), 1_000_000L, 120, Kind.GAMING)!!
        assertEquals(40.0, min, 0.26)
        assertEquals(BreakType.EYE, d.type)
    }

    @Test fun bodyBreakAfter60MinutesWhenEyeBreaksTaken() {
        val r = fresh()
        var now = 1_000_000L
        var bodyAt = -1.0
        while (now < 1_000_000L + 90 * 60_000L) {
            now += 15_000L
            val d = r.tick(now, step, Kind.READING, false, false)
            if (d.prompt == Prompt.NUDGE) {
                if (d.type == BreakType.BODY) { bodyAt = (now - 1_000_000L) / 60_000.0; break }
                r.finish(BreakType.EYE, now)
            }
        }
        assertEquals(60.0, bodyAt, 0.26)
    }

    @Test fun mixedActivityFillsProportionally() {
        // 10 min reading = half the eye load, then 20 min gaming = the other half.
        val r = fresh()
        var now = 1_000_000L
        repeat(40) { now += 15_000L; assertEquals(Prompt.NONE, r.tick(now, step, Kind.READING, false, false).prompt) }
        val (min, _) = runUntilPrompt(r, now, 60, Kind.GAMING)!!
        assertEquals(20.0, min, 0.26)
    }

    @Test fun fiveMinutesAwayRestsEyesButNotBody() {
        val r = fresh()
        var now = 1_000_000L
        repeat(60) { now += 15_000L; r.tick(now, step, Kind.READING, false, false) } // 15 min
        r.screenOff(now)
        now += 5 * 60_000L
        assertTrue(r.screenOn(now))
        assertEquals(0.0, r.eyeLoad, 1e-9)
        assertEquals(0.25, r.bodyLoad, 1e-6)
    }

    @Test fun shortScreenOffIsNotARest() {
        val r = fresh()
        var now = 1_000_000L
        repeat(40) { now += 15_000L; r.tick(now, step, Kind.READING, false, false) }
        r.screenOff(now)
        now += 60_000L
        assertFalse(r.screenOn(now))
        assertEquals(0.5, r.eyeLoad, 1e-6)
    }

    @Test fun fifteenMinutesAwayRestsEverything() {
        val r = fresh()
        var now = 1_000_000L
        repeat(100) { now += 15_000L; r.tick(now, step, Kind.READING, false, false) }
        r.screenOff(now)
        now += 15 * 60_000L
        r.screenOn(now)
        assertEquals(0.0, r.bodyLoad, 1e-9)
        assertEquals(0L, r.sessionSec(now))
    }

    @Test fun watchingWaitsForVideoToPause() {
        val start = 1_000_000L
        val pauseAt = start + 33 * 60_000L // video stops 3 minutes after the break is due
        val (min, d) = runUntilPrompt(fresh(start), start, 120, Kind.WATCHING, media = { it < pauseAt })!!
        assertEquals(33.0, min, 0.26)
        assertEquals(Prompt.NUDGE, d.prompt)
    }

    @Test fun watchingGivesUpWaitingAfter10Minutes() {
        val (min, _) = runUntilPrompt(fresh(), 1_000_000L, 120, Kind.WATCHING, media = { true })!!
        assertEquals(40.0, min, 0.26)
    }

    @Test fun gamingDoesNotWaitForAudio() {
        val (min, _) = runUntilPrompt(fresh(), 1_000_000L, 120, Kind.GAMING, media = { true })!!
        assertEquals(40.0, min, 0.26)
    }

    @Test fun callsHoldTheBreak() {
        assertNull(runUntilPrompt(fresh(), 1_000_000L, 60, Kind.READING, call = true))
    }

    @Test fun ignoredRemindersComeBackAndGetFirm() {
        // Body break pushed out of the way so only the eye reminder is in play.
        val r = BreakRules(RuleConfig(bodyMin = 120)).also { it.screenOn(1_000_000L) }
        val start = 1_000_000L
        val prompts = mutableListOf<Pair<Double, Prompt>>()
        var now = start
        while (now < start + 70 * 60_000L && prompts.size < 3) {
            now += 15_000L
            val d = r.tick(now, step, Kind.GAMING, false, false)
            if (d.prompt == Prompt.NUDGE || d.prompt == Prompt.FIRM) prompts += (now - start) / 60_000.0 to d.prompt
        }
        assertEquals(listOf(Prompt.NUDGE, Prompt.NUDGE, Prompt.FIRM), prompts.map { it.second })
        assertEquals(40.0, prompts[0].first, 0.26)
        assertEquals(50.0, prompts[1].first, 0.26)
        assertEquals(60.0, prompts[2].first, 0.26)
    }

    @Test fun snoozeWaitsTenMinutes() {
        val r = fresh()
        val (min, _) = runUntilPrompt(r, 1_000_000L, 60, Kind.READING)!!
        val now = 1_000_000L + (min * 60_000).toLong()
        r.snooze(now)
        val (again, d) = runUntilPrompt(r, now, 60, Kind.READING)!!
        assertEquals(10.0, again, 0.26)
        assertEquals(Prompt.NUDGE, d.prompt)
    }

    @Test fun finishStartsOver() {
        val r = fresh()
        val (min, _) = runUntilPrompt(r, 1_000_000L, 60, Kind.READING)!!
        val now = 1_000_000L + (min * 60_000).toLong()
        r.finish(BreakType.EYE, now)
        assertNull(r.pending)
        assertEquals(20 * 60, r.secondsToEye(Kind.READING))
        val (again, _) = runUntilPrompt(r, now, 60, Kind.READING)!!
        assertEquals(20.0, again, 0.26)
    }

    @Test fun secondsToNextUsesActivity() {
        val r = fresh()
        assertEquals(20 * 60, r.secondsToNext(Kind.READING))
        assertEquals(40 * 60, r.secondsToNext(Kind.GAMING))
        assertEquals(BreakType.EYE, r.nextType(Kind.GAMING))
    }

    @Test fun bedtimeWindowWrapsPastMidnight() {
        assertTrue(Tips.inWindow(23 * 60 + 30, 23 * 60, 6 * 60))
        assertTrue(Tips.inWindow(2 * 60, 23 * 60, 6 * 60))
        assertFalse(Tips.inWindow(12 * 60, 23 * 60, 6 * 60))
        assertTrue(Tips.inWindow(13 * 60, 12 * 60, 14 * 60))
        assertFalse(Tips.inWindow(5, 0, 0))
    }

    @Test fun lateNightTipAfterFiveMinutesThenEveryHalfHour() {
        val t = Tips()
        var now = 0L
        val tips = mutableListOf<Double>()
        repeat(4 * 60 * 2) { // 2 hours of 15 s ticks
            now += 15_000L
            if (t.tick(now, step, lateNow = true, lux = 100f, darkTipsOn = true) == Tips.Tip.LATE_NIGHT) tips += now / 60_000.0
        }
        assertEquals(listOf(5.0, 35.0, 65.0, 95.0), tips)
    }

    @Test fun darkRoomTipAfterThreeMinutesOncePerHour() {
        val t = Tips()
        var now = 0L
        val tips = mutableListOf<Double>()
        repeat(4 * 90) {
            now += 15_000L
            if (t.tick(now, step, lateNow = false, lux = 2f, darkTipsOn = true) == Tips.Tip.DARK_ROOM) tips += now / 60_000.0
        }
        // Dark from the first tick (0.25 min), so the tip comes 3 minutes later.
        assertEquals(listOf(3.25, 63.25), tips)
        assertNull(Tips().tick(1000L, step, false, -1f, true))
    }
}
