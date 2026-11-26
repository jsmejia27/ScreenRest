package net.jilbert.screenrest

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/** Builds every notification. Texts in English or Tagalog, following the app language. */
class Notifier(private val ctx: Context, private val prefs: Prefs) {
    private val nm = ctx.getSystemService(NotificationManager::class.java)

    companion object {
        const val CH_STATUS = "status"
        const val CH_BREAKS = "breaks"
        const val CH_TIPS = "tips"
        const val ID_STATUS = 1
        const val ID_BREAK = 2
        const val ID_TIP = 3
    }

    private fun t(en: String, tl: String) = prefs.t(en, tl)

    fun kindName(k: Kind): String = when (k) {
        Kind.READING -> t("Reading", "Pagbabasa")
        Kind.WATCHING -> t("Watching", "Panonood")
        Kind.GAMING -> t("Gaming", "Paglalaro")
        Kind.OTHER -> t("Other", "Iba pa")
    }

    fun createChannels() {
        val status = NotificationChannel(CH_STATUS, t("Status", "Status"), NotificationManager.IMPORTANCE_LOW).apply {
            description = t("Shows when your next break is.", "Ipinapakita kung kailan ang susunod mong break.")
            setShowBadge(false)
        }
        val breaks = NotificationChannel(CH_BREAKS, t("Break reminders", "Paalala sa break"), NotificationManager.IMPORTANCE_HIGH).apply {
            description = t("Eye and stretch break reminders.", "Paalala para sa break ng mata at pag-unat.")
            setSound(null, null)
            enableVibration(false) // vibrates in code, following the sound setting
        }
        val tips = NotificationChannel(CH_TIPS, t("Tips", "Mga tip"), NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = t("Late-night and dark-room tips.", "Mga tip sa gabi at sa madilim na kuwarto.")
            setSound(null, null)
        }
        nm.createNotificationChannels(listOf(status, breaks, tips))
    }

    private fun openApp(req: Int, type: BreakType? = null, kind: Kind? = null): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (type != null) {
            i.putExtra(MainActivity.EXTRA_BREAK, type.key)
            i.putExtra(MainActivity.EXTRA_KIND, (kind ?: Kind.OTHER).key)
        }
        return PendingIntent.getActivity(ctx, req, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    private fun serviceAction(req: Int, action: String, type: BreakType? = null): PendingIntent {
        val i = Intent(ctx, BreakService::class.java).setAction(action)
        if (type != null) i.putExtra(BreakService.EXTRA_TYPE, type.key)
        return PendingIntent.getService(ctx, req, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    fun status(text: String, paused: Boolean): Notification {
        val b = Notification.Builder(ctx, CH_STATUS)
            .setSmallIcon(R.drawable.ic_stat_eye)
            .setContentTitle(if (paused) t("ScreenRest is paused", "Naka-pause ang ScreenRest") else t("ScreenRest is on", "Naka-on ang ScreenRest"))
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setContentIntent(openApp(10))
        if (paused) {
            b.addAction(Notification.Action.Builder(null, t("Resume", "Ituloy"), serviceAction(11, BreakService.ACTION_RESUME)).build())
        } else {
            b.addAction(Notification.Action.Builder(null, t("Pause 1 hour", "I-pause nang 1 oras"), serviceAction(12, BreakService.ACTION_PAUSE)).build())
        }
        return b.build()
    }

    fun showStatus(text: String, paused: Boolean) = nm.notify(ID_STATUS, status(text, paused))

    fun breakTexts(type: BreakType, kind: Kind, firm: Boolean): Pair<String, String> {
        val (title, body) = when {
            type == BreakType.BODY && kind == Kind.GAMING -> t("Time to rest your hands", "Oras na para ipahinga ang mga kamay") to
                t("A 1-minute thumb and wrist stretch. Finish your match first.", "1 minutong pag-unat ng hinlalaki at pulso. Tapusin muna ang laban.")
            type == BreakType.BODY -> t("Time for a stretch break", "Oras na para mag-unat") to
                t("1 minute for your neck, shoulders and eyes.", "1 minuto para sa leeg, balikat at mata.")
            kind == Kind.GAMING -> t("Eye break after this match", "Break ng mata pagkatapos ng laban") to
                t("Look far away and blink for 20 seconds.", "Tumingin sa malayo at kumurap nang 20 segundo.")
            kind == Kind.WATCHING -> t("Good moment for an eye break", "Magandang pagkakataon para sa break ng mata") to
                t("Look far away for 20 seconds, then carry on watching.", "Tumingin sa malayo nang 20 segundo, saka ituloy ang panonood.")
            else -> t("Rest your eyes: 20 seconds", "Ipahinga ang mata: 20 segundo") to
                t("Look at something far away and blink slowly.", "Tumingin sa malayong bagay at dahan-dahang kumurap.")
        }
        return if (firm) t("Please take your break now", "Pakiusap, mag-break ka na") to title else title to body
    }

    fun showBreak(type: BreakType, kind: Kind, firm: Boolean) {
        val (title, body) = breakTexts(type, kind, firm)
        val n = Notification.Builder(ctx, CH_BREAKS)
            .setSmallIcon(R.drawable.ic_stat_eye)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(openApp(20, type, kind))
            .addAction(Notification.Action.Builder(null, t("Start", "Simulan"), openApp(21, type, kind)).build())
            .addAction(Notification.Action.Builder(null, t("Later (10 min)", "Mamaya (10 min)"), serviceAction(22, BreakService.ACTION_SNOOZE)).build())
            .addAction(Notification.Action.Builder(null, t("Skip", "Laktawan"), serviceAction(23, BreakService.ACTION_SKIP, type)).build())
            .build()
        nm.notify(ID_BREAK, n)
        if (prefs.sound != "silent") vibrate(if (firm) longArrayOf(0, 250, 150, 250, 150, 250) else longArrayOf(0, 200, 120, 200))
    }

    fun cancelBreak() = nm.cancel(ID_BREAK)

    fun showTip(tip: Tips.Tip) {
        val (title, body) = when (tip) {
            Tips.Tip.LATE_NIGHT -> t("It's getting late", "Gabi na") to
                t("Screens before bed make it harder to fall asleep. Finish up soon and rest your eyes.",
                    "Ang screen bago matulog ay nagpapahirap makatulog. Tapusin na at ipahinga ang mata.")
            Tips.Tip.DARK_ROOM -> t("Dark room, bright screen", "Madilim ang kuwarto, maliwanag ang screen") to
                t("Turn down the brightness, or turn on Night Light or eye comfort mode.",
                    "Hinaan ang liwanag, o i-on ang Night Light o eye comfort mode.")
        }
        val n = Notification.Builder(ctx, CH_TIPS)
            .setSmallIcon(R.drawable.ic_stat_eye)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setTimeoutAfter(10 * 60_000L)
            .setContentIntent(openApp(30))
            .build()
        nm.notify(ID_TIP, n)
    }

    private fun vibrate(pattern: LongArray) {
        val v: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
            ctx.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            ctx.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (v.hasVibrator()) v.vibrate(VibrationEffect.createWaveform(pattern, -1))
    }
}
