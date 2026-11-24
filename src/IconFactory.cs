using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace ScreenRest
{
    /// <summary>Draws the ScreenRest "eye" icon in code, so the app ships as a single .exe.</summary>
    public static class IconFactory
    {
        public static readonly Color Brand = Color.FromArgb(30, 158, 138);
        public static readonly Color Paused = Color.FromArgb(120, 128, 136);
        public static readonly Color Due = Color.FromArgb(232, 140, 40);

        [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);

        public static Bitmap Draw(int size, Color c)
        {
            var b = new Bitmap(size, size, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(b))
            using (var br = new SolidBrush(c))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.Transparent);
                float p = size * 0.03f;
                g.FillEllipse(br, p, p, size - 2 * p, size - 2 * p);
                float w = size * 0.74f, h = size * 0.42f, x = (size - w) / 2f, y = (size - h) / 2f, mid = size / 2f;
                using (var path = new GraphicsPath())
                {
                    path.AddBezier(x, mid, x + w * 0.25f, y - h * 0.2f, x + w * 0.75f, y - h * 0.2f, x + w, mid);
                    path.AddBezier(x + w, mid, x + w * 0.75f, y + h * 1.2f, x + w * 0.25f, y + h * 1.2f, x, mid);
                    g.FillPath(Brushes.White, path);
                }
                float r = size * 0.14f;
                g.FillEllipse(br, mid - r, mid - r, 2 * r, 2 * r);
            }
            return b;
        }

        public static Icon MakeIcon(Color c)
        {
            using (var b = Draw(32, c))
            {
                IntPtr h = b.GetHicon();
                var ic = (Icon)Icon.FromHandle(h).Clone();
                DestroyIcon(h);
                return ic;
            }
        }

        /// <summary>Tray icon showing a short number (minutes to the next break) in white on a rounded square.</summary>
        public static Icon MakeNumberIcon(string text, Color c)
        {
            using (var b = new Bitmap(32, 32, PixelFormat.Format32bppArgb))
            {
                using (var g = Graphics.FromImage(b))
                using (var br = new SolidBrush(c))
                using (var path = new GraphicsPath())
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    g.Clear(Color.Transparent);
                    const float r = 7;
                    path.AddArc(0, 0, 2 * r, 2 * r, 180, 90);
                    path.AddArc(32 - 2 * r, 0, 2 * r, 2 * r, 270, 90);
                    path.AddArc(32 - 2 * r, 32 - 2 * r, 2 * r, 2 * r, 0, 90);
                    path.AddArc(0, 32 - 2 * r, 2 * r, 2 * r, 90, 90);
                    path.CloseFigure();
                    g.FillPath(br, path);
                    // Tight letter spacing so two digits stay readable at 16 px
                    using (var f = new Font("Segoe UI", text.Length > 1 ? 23f : 27f, FontStyle.Bold, GraphicsUnit.Pixel))
                    using (var sf = new StringFormat(StringFormat.GenericTypographic) { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
                        g.DrawString(text, f, Brushes.White, new RectangleF(-4, 1, 40, 32), sf);
                }
                IntPtr h = b.GetHicon();
                var ic = (Icon)Icon.FromHandle(h).Clone();
                DestroyIcon(h);
                return ic;
            }
        }

        /// <summary>Writes a multi-size PNG-compressed .ico (used by build.ps1 for the exe icon).</summary>
        public static void SaveIco(string path)
        {
            int[] sizes = { 16, 24, 32, 48, 64, 256 };
            var pngs = new byte[sizes.Length][];
            for (int i = 0; i < sizes.Length; i++)
                using (var b = Draw(sizes[i], Brand))
                using (var ms = new MemoryStream()) { b.Save(ms, ImageFormat.Png); pngs[i] = ms.ToArray(); }

            using (var fs = File.Create(path))
            using (var w = new BinaryWriter(fs))
            {
                w.Write((short)0); w.Write((short)1); w.Write((short)sizes.Length);
                int offset = 6 + 16 * sizes.Length;
                for (int i = 0; i < sizes.Length; i++)
                {
                    w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                    w.Write((byte)(sizes[i] >= 256 ? 0 : sizes[i]));
                    w.Write((byte)0); w.Write((byte)0);
                    w.Write((short)1); w.Write((short)32);
                    w.Write(pngs[i].Length); w.Write(offset);
                    offset += pngs[i].Length;
                }
                foreach (var p in pngs) w.Write(p);
            }
        }
    }
}
