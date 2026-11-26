package net.jilbert.screenrest

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.util.LruCache
import java.io.ByteArrayOutputStream

/** Loads other apps' launcher icons, for the report and the app list. */
object AppIcons {
    private const val SIZE = 96 // px; shown at 28-40 dp in the app and ~20 pt in the PDF
    private val cache = LruCache<String, Bitmap>(80)

    /** The app's icon as a square bitmap, or null when it isn't installed (any more) or can't be seen. */
    fun bitmap(ctx: Context, pkg: String): Bitmap? {
        cache.get(pkg)?.let { return it }
        val d = try {
            ctx.packageManager.getApplicationIcon(pkg)
        } catch (_: Exception) {
            return null
        }
        return render(d).also { cache.put(pkg, it) }
    }

    /** The same icon as PNG bytes, for Flutter's Image.memory. */
    fun png(ctx: Context, pkg: String): ByteArray? {
        val b = bitmap(ctx, pkg) ?: return null
        return ByteArrayOutputStream().use { out ->
            b.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    }

    fun render(d: Drawable, size: Int = SIZE): Bitmap {
        val b = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(b)
        d.setBounds(0, 0, size, size)
        d.draw(c)
        return b
    }
}
