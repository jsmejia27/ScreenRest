package net.jilbert.screenrest

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import androidx.core.content.FileProvider
import java.io.File

/**
 * Draws the "Your week" report as an A4 PDF and opens the share sheet for it.
 * Flutter sends everything already translated and formatted (see dashboard.dart, _exportPdf),
 * so this class only lays it out.
 */
class ReportPdf(private val ctx: Context, private val data: Map<*, *>) {
    private companion object {
        const val W = 595f      // A4 in points
        const val H = 842f
        const val M = 44f       // page margin
        const val FOOT = 34f    // space kept for the footer
        val INK = Color.rgb(0x16, 0x20, 0x28)
        val DIM = Color.rgb(0x6B, 0x7A, 0x84)
        val LINE = Color.rgb(0xE2, 0xE8, 0xEC)
        val TILE = Color.rgb(0xF2, 0xF5, 0xF6)
        val TEAL = Color.rgb(0x1E, 0x9E, 0x8A)
        val WARN = Color.rgb(0xD9, 0x8A, 0x2B)
    }

    private val doc = PdfDocument()
    private var page: PdfDocument.Page? = null
    private lateinit var c: Canvas
    private var y = M
    private var pageNo = 0
    private val cw = W - 2 * M

    private fun paint(size: Float, color: Int = INK, bold: Boolean = false, align: Paint.Align = Paint.Align.LEFT) =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            this.color = color
            typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            textAlign = align
        }

    private fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }

    private fun str(k: String, m: Map<*, *> = data) = m[k] as? String ?: ""
    private fun num(k: String, m: Map<*, *>) = (m[k] as? Number)?.toFloat() ?: 0f
    private fun list(k: String, m: Map<*, *> = data) = (m[k] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
    private fun strings(k: String) = (data[k] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
    private fun kindColor(kind: String): Int {
        val hex = (data["kindColors"] as? Map<*, *>)?.get(kind) as? String
        return try { Color.parseColor(hex ?: "#82919B") } catch (_: Exception) { DIM }
    }

    /** Builds the PDF in the cache folder and returns the file. */
    fun write(): File {
        newPage()
        header()
        score()
        apps()
        chart()
        totals()
        finishPage()
        val dir = File(ctx.cacheDir, "reports").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() } // keep only the newest report
        val name = str("fileName").ifEmpty { "ScreenRest-report.pdf" }.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val file = File(dir, name)
        file.outputStream().use { doc.writeTo(it) }
        doc.close()
        return file
    }

    /** Opens Android's share sheet for [file] (save to Files, Drive, email, print...). */
    fun share(file: File) {
        val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, str("title"))
            clipData = ClipData.newRawUri(file.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        ctx.startActivity(Intent.createChooser(send, str("shareTitle")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    // ---- pages ----

    private fun newPage() {
        pageNo++
        val p = doc.startPage(PdfDocument.PageInfo.Builder(W.toInt(), H.toInt(), pageNo).create())
        page = p
        c = p.canvas
        y = M
    }

    private fun finishPage() {
        val p = page ?: return
        c.drawLine(M, H - FOOT + 6, W - M, H - FOOT + 6, fill(LINE))
        c.drawText(str("footer"), M, H - FOOT + 20, paint(8f, DIM))
        c.drawText("$pageNo", W - M, H - FOOT + 20, paint(8f, DIM, align = Paint.Align.RIGHT))
        doc.finishPage(p)
        page = null
    }

    /** Starts a new page when the next [h] points won't fit on this one. */
    private fun need(h: Float) {
        if (y + h > H - FOOT - 8) {
            finishPage()
            newPage()
        }
    }

    private fun sectionTitle(t: String) {
        need(40f)
        y += 22f
        c.drawText(t, M, y, paint(9f, TEAL, bold = true).apply { letterSpacing = 0.08f })
        y += 12f
    }

    // ---- sections ----

    private fun header() {
        val logo = try { AppIcons.render(ctx.packageManager.getApplicationIcon(ctx.packageName), 144) } catch (_: Exception) { null }
        if (logo != null) c.drawBitmap(logo, null, RectF(M, y, M + 40, y + 40), fill(Color.BLACK))
        val x = if (logo != null) M + 52 else M
        c.drawText(str("title"), x, y + 19, paint(20f, INK, bold = true))
        c.drawText(str("subtitle"), x, y + 35, paint(10f, DIM))
        y += 52f
        c.drawLine(M, y, W - M, y, fill(LINE))
    }

    private fun score() {
        sectionTitle(str("scoreTitle"))
        val value = data["score"] as? Number
        if (value == null) {
            y += 12f
            c.drawText(str("noScore"), M, y, paint(10.5f, DIM))
            y += 6f
            return
        }
        val v = value.toInt()
        y += 34f
        val big = paint(36f, INK, bold = true)
        c.drawText("$v", M, y, big)
        c.drawText(str("scoreLabel"), M + big.measureText("$v") + 10, y, paint(14f, if (v >= 60) TEAL else WARN, bold = true))
        y += 8f
        for ((items, color) in listOf(strings("good") to TEAL, strings("bad") to WARN)) {
            for (t in items) {
                need(16f)
                y += 15f
                c.drawCircle(M + 4, y - 3.5f, 3f, fill(color))
                c.drawText(t, M + 14, y, paint(10.5f))
            }
        }
    }

    private fun apps() {
        sectionTitle(str("appsTitle"))
        val apps = list("apps")
        if (apps.isEmpty()) {
            y += 12f
            c.drawText(str("noApps"), M, y, paint(10.5f, DIM))
            y += 6f
            return
        }
        val iconSize = 22f
        val textX = M + iconSize + 10
        val barW = cw - (textX - M)
        for (a in apps) {
            need(42f)
            y += 6f
            val color = kindColor(str("kind", a))
            val icon = AppIcons.bitmap(ctx, str("pkg", a))
            if (icon != null) {
                c.drawBitmap(icon, null, RectF(M, y, M + iconSize, y + iconSize), fill(Color.BLACK))
            } else {
                c.drawRoundRect(RectF(M, y, M + iconSize, y + iconSize), 6f, 6f, fill(TILE))
                c.drawCircle(M + iconSize / 2, y + iconSize / 2, 4f, fill(color))
            }
            val time = str("time", a)
            val timeP = paint(10.5f, INK, bold = true, align = Paint.Align.RIGHT)
            val label = ellipsize(str("label", a), paint(10.5f), barW - timeP.measureText(time) - 12)
            c.drawText(label, textX, y + 10, paint(10.5f))
            c.drawText(time, W - M, y + 10, timeP)
            val top = y + 15
            c.drawRoundRect(RectF(textX, top, textX + barW, top + 4), 2f, 2f, fill(TILE))
            val frac = num("frac", a).coerceIn(0f, 1f)
            if (frac > 0) c.drawRoundRect(RectF(textX, top, textX + maxOf(4f, barW * frac), top + 4), 2f, 2f, fill(color))
            val late = a["late"] == true
            c.drawText(str("detail", a), textX, top + 15, paint(8.5f, if (late) WARN else DIM))
            y = top + 22
        }
    }

    private fun chart() {
        val days = list("days")
        if (days.isEmpty()) return
        sectionTitle(str("chartTitle"))
        val chartH = 120f
        need(chartH + 52f)
        val order = listOf("other", "gaming", "watching", "reading") // drawn bottom to top
        val maxTotal = maxOf(60f, days.maxOf { num("total", it) })
        val slot = cw / days.size
        val barW = minOf(34f, slot * 0.5f)
        val base = y + 14 + chartH
        for ((i, d) in days.withIndex()) {
            val cx = M + slot * i + slot / 2
            val total = num("total", d)
            val h = chartH * (total / maxTotal)
            c.drawRoundRect(RectF(cx - barW / 2, base - maxOf(h, 2f), cx + barW / 2, base), 4f, 4f, fill(TILE))
            var top = base
            for (k in order) {
                val part = num(k, d)
                if (part <= 0 || total <= 0) continue
                val ph = h * (part / total)
                c.drawRect(cx - barW / 2, top - ph, cx + barW / 2, top, fill(kindColor(k)))
                top -= ph
            }
            c.drawText(str("totalText", d), cx, base - h - 5, paint(8f, DIM, align = Paint.Align.CENTER))
            c.drawText(str("day", d), cx, base + 14, paint(9f, INK, align = Paint.Align.CENTER))
        }
        y = base + 30
        // legend
        var x = M
        val labels = data["kindLabels"] as? Map<*, *> ?: emptyMap<String, String>()
        for (k in order.reversed()) {
            val t = labels[k] as? String ?: k
            c.drawRoundRect(RectF(x, y - 7, x + 8, y + 1), 2f, 2f, fill(kindColor(k)))
            val p = paint(9f, DIM)
            c.drawText(t, x + 12, y, p)
            x += 12 + p.measureText(t) + 18
        }
        y += 4f
    }

    private fun totals() {
        val totals = list("totals")
        if (totals.isEmpty()) return
        sectionTitle(str("totalsTitle"))
        val gap = 10f
        val tileW = (cw - gap) / 2
        val tileH = 44f
        for (row in totals.chunked(2)) {
            need(tileH + gap)
            for ((i, t) in row.withIndex()) {
                val x = M + i * (tileW + gap)
                c.drawRoundRect(RectF(x, y, x + tileW, y + tileH), 8f, 8f, fill(TILE))
                c.drawText(str("value", t), x + 12, y + 20, paint(14f, INK, bold = true))
                c.drawText(ellipsize(str("label", t), paint(9f), tileW - 24), x + 12, y + 35, paint(9f, DIM))
            }
            y += tileH + gap
        }
    }

    private fun ellipsize(s: String, p: Paint, max: Float): String {
        if (p.measureText(s) <= max) return s
        var t = s
        while (t.isNotEmpty() && p.measureText("$t…") > max) t = t.dropLast(1)
        return "$t…"
    }
}
