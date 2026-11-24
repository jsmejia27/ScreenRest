using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace ScreenRest
{
    /// <summary>
    /// One-page A4 PDF of the last 30 days, written to show an optometrist or doctor: break habits, average
    /// screen time, and the eye-blur and energy check-ins, with how they're scored. Same page as the Mac app.
    /// The page is drawn with GDI+ and embedded as one lossless image, so no PDF library is needed.
    /// </summary>
    public static class ReportPdf
    {
        const float PageW = 595, PageH = 842; // A4 in points
        const int Dpi = 200;

        /// <summary>Asks where to save, writes the PDF and shows it in File Explorer.</summary>
        public static void ExportWithDialog(IWin32Window owner, Func<DayStats> today)
        {
            using (var dlg = new SaveFileDialog())
            {
                dlg.Filter = "PDF (*.pdf)|*.pdf";
                dlg.FileName = "ScreenRest report " + DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + ".pdf";
                dlg.Title = L.T("A one-page summary of the last 30 days, for your optometrist or doctor",
                                "Isang pahinang buod ng huling 30 araw, para sa optometrist o doktor mo");
                if (dlg.ShowDialog(owner) != DialogResult.OK) return;
                try
                {
                    Write(dlg.FileName, today);
                    try { Process.Start("explorer.exe", "/select,\"" + dlg.FileName + "\""); } catch { }
                }
                catch (Exception ex)
                {
                    MessageBox.Show(owner, L.T("Couldn't save the report: ", "Hindi na-save ang report: ") + ex.Message,
                        "ScreenRest", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
        }

        public static void Write(string path, Func<DayStats> today)
        {
            using (var bmp = Render(today, Dpi))
                WriteImagePdf(path, bmp, PageW, PageH, "ScreenRest health report");
        }

        /// <summary>The report page as an image at the given resolution (also handy for screenshots).</summary>
        public static Bitmap Render(Func<DayStats> today, int dpi)
        {
            var model = new DashboardModel(30, today, () => false);
            var bmp = new Bitmap((int)Math.Round(PageW * dpi / 72f), (int)Math.Round(PageH * dpi / 72f), PixelFormat.Format24bppRgb);
            bmp.SetResolution(72, 72); // one drawing unit = one point; ScaleTransform below adds the detail
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.White);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.ScaleTransform(dpi / 72f, dpi / 72f);
                DrawPage(g, model);
            }
            return bmp;
        }

        static void DrawPage(Graphics g, DashboardModel m)
        {
            const float k = 0.75f; // chart sizes are in 96-dpi pixels; here a unit is a point
            float left = 36, width = PageW - 72, y = 36;
            var c = m.Current;
            var start = DateTime.Today.AddDays(-29);

            using (var fTitle = new Font("Segoe UI Semibold", 15f))
            using (var fSub = new Font("Segoe UI", 8f))
            using (var fSection = new Font("Segoe UI Semibold", 10.5f))
            using (var fLabel = new Font("Segoe UI", 8.5f))
            using (var fValue = new Font("Segoe UI Semibold", 8.5f))
            using (var fChart = new Font("Segoe UI", 7f))
            using (var fBody = new Font("Segoe UI", 8.5f))
            using (var fNote = new Font("Segoe UI", 7f))
            using (var line = new Pen(DashPaint.Border, 0.75f))
            {
                // Header
                using (var logo = IconFactory.Draw(176, IconFactory.Brand)) g.DrawImage(logo, left, y, 44, 44);
                DashPaint.Text(g, L.T("Screen break and eye-comfort report", "Report sa screen break at ginhawa ng mata"), fTitle, DashPaint.Ink, left + 56, y + 4);
                DashPaint.Text(g, L.Date(start, "d MMM yyyy") + " – " + L.Date(DateTime.Today, "d MMM yyyy") +
                    L.T("  ·  last 30 days  ·  made with ScreenRest", "  ·  huling 30 araw  ·  gawa ng ScreenRest"), fSub, DashPaint.Ink2, left + 57, y + 28);
                y += 56;
                g.DrawLine(line, left, y, left + width, y);
                y += 12;

                // Summary table
                Row(g, fLabel, fValue, left, ref y,
                    L.T("Days tracked", "Araw na naitala"), c.Days.ToString(),
                    L.T("Average active screen time", "Karaniwang aktibong oras sa screen"), DayStats.Duration(c.ActivePerDay) + L.T(" / day", " / araw"));
                Row(g, fLabel, fValue, left, ref y,
                    L.T("Breaks taken (score)", "Breaks na ginawa (score)"), c.Score.HasValue ? c.Score + "%" : "–",
                    L.T("Breaks postponed", "Ipinagpaliban"), c.Postponed.ToString());
                Row(g, fLabel, fValue, left, ref y,
                    L.T("Eye breaks (20-20-20)", "Eye breaks (20-20-20)"), c.EyeT + " / " + c.EyeAll + "  (" + PeriodTotals.PctText(c.EyeT, c.EyeAll) + ")",
                    L.T("Stretch breaks", "Stretch breaks"), c.StrT + " / " + c.StrAll + "  (" + PeriodTotals.PctText(c.StrT, c.StrAll) + ")");
                Row(g, fLabel, fValue, left, ref y,
                    L.T("Average right-eye blur", "Karaniwang labo ng kanang mata"), Avg(c.AvgBlur) + " / 5  (n=" + c.BlurN + ")",
                    L.T("Average energy", "Karaniwang lakas"), Avg(c.AvgEnergy) + " / 5  (n=" + c.EnergyN + ")");
                y += 8;

                // Ratings chart
                DashPaint.Text(g, L.T("Daily check-in: right-eye blur and energy", "Araw-araw na check-in: labo ng kanang mata at lakas"), fSection, DashPaint.Ink, left, y);
                y += 20;
                if (!m.HasRatings)
                {
                    DashPaint.Text(g, L.T("No check-ins in this period.", "Walang check-in sa panahong ito."), fBody, DashPaint.Ink2, left, y);
                    y += 24;
                }
                else
                {
                    DashPaint.RatingsChart(g, new RectangleF(left, y, width, 170), m, fChart, k);
                    y += 182;
                }

                // Breaks chart
                DashPaint.Text(g, L.T("Breaks per day", "Breaks bawat araw"), fSection, DashPaint.Ink, left, y);
                y += 20;
                DashPaint.BreaksChart(g, new RectangleF(left, y, width, 150), m, fChart, k);
                y += 164;

                // Observations
                DashPaint.Text(g, L.T("Observations", "Mga obserbasyon"), fSection, DashPaint.Ink, left, y);
                y += 20;
                foreach (var i in m.Insights)
                {
                    DashPaint.Text(g, "•", fBody, DashPaint.Ink, left, y);
                    y += DashPaint.Wrapped(g, i.Text, fBody, DashPaint.Ink, left + 10, y, width - 10) + 4;
                }

                // How to read this, at the foot of the page
                string how = L.T("How to read this: the person rates their right eye's blurriness at the end of each workday from 1 (clear) to 5 (very blurry), and their energy from 1 (exhausted) to 5 (great). Breaks follow the 20-20-20 rule (a 20-second look into the distance every 20 minutes) plus a stand-up stretch break about every hour. Ratings are self-reported. ScreenRest is a wellness reminder, not a medical device.",
                    "Paano basahin: sa dulo ng bawat araw ng trabaho, nire-rate ng tao ang labo ng kanang mata mula 1 (malinaw) hanggang 5 (napakalabo), at ang lakas mula 1 (pagod na pagod) hanggang 5 (napakasigla). Sumusunod ang breaks sa 20-20-20 rule (20 segundong pagtingin sa malayo tuwing 20 minuto) at stretch break nang nakatayo halos bawat oras. Sariling rating ito ng tao. Paalala sa kalusugan ang ScreenRest, hindi medical device.");
                float hh = g.MeasureString(how, fNote, (int)width).Height;
                float fy = Math.Max(y + 12, PageH - 36 - hh);
                g.DrawLine(line, left, fy - 8, left + width, fy - 8);
                DashPaint.Wrapped(g, how, fNote, DashPaint.Ink2, left, fy, width);
            }
        }

        static string Avg(double? v) { return v.HasValue ? v.Value.ToString("0.0") : "–"; }

        static void Row(Graphics g, Font fLabel, Font fValue, float left, ref float y, string a, string av, string b, string bv)
        {
            DashPaint.Text(g, a, fLabel, DashPaint.Ink2, left, y);
            DashPaint.Text(g, av, fValue, DashPaint.Ink, left + 150, y);
            DashPaint.Text(g, b, fLabel, DashPaint.Ink2, left + 280, y);
            DashPaint.Text(g, bv, fValue, DashPaint.Ink, left + 440, y);
            y += 17;
        }

        // ------------------------------------------------------------------ minimal PDF writer
        /// <summary>Writes a one-page PDF whose page is the bitmap, stored losslessly (FlateDecode).</summary>
        public static void WriteImagePdf(string path, Bitmap bmp, float widthPt, float heightPt, string title)
        {
            byte[] pixels = RgbBytes(bmp);
            byte[] image = Zlib(pixels);
            byte[] content = Encoding.ASCII.GetBytes(string.Format(CultureInfo.InvariantCulture,
                "q {0:0.##} 0 0 {1:0.##} 0 0 cm /Im0 Do Q", widthPt, heightPt));

            using (var ms = new MemoryStream())
            {
                var offsets = new long[7];
                Action<string> put = s => { var b = Encoding.ASCII.GetBytes(s); ms.Write(b, 0, b.Length); };
                put("%PDF-1.4\n");
                offsets[1] = ms.Position; put("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n");
                offsets[2] = ms.Position; put("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n");
                offsets[3] = ms.Position; put(string.Format(CultureInfo.InvariantCulture,
                    "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {0:0.##} {1:0.##}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>\nendobj\n",
                    widthPt, heightPt));
                offsets[4] = ms.Position; put(string.Format(CultureInfo.InvariantCulture,
                    "4 0 obj\n<< /Type /XObject /Subtype /Image /Width {0} /Height {1} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length {2} >>\nstream\n",
                    bmp.Width, bmp.Height, image.Length));
                ms.Write(image, 0, image.Length);
                put("\nendstream\nendobj\n");
                offsets[5] = ms.Position; put("5 0 obj\n<< /Length " + content.Length + " >>\nstream\n");
                ms.Write(content, 0, content.Length);
                put("\nendstream\nendobj\n");
                offsets[6] = ms.Position; put("6 0 obj\n<< /Title (" + PdfString(title) + ") /Creator (ScreenRest) /Producer (ScreenRest) /CreationDate (D:" +
                    DateTime.Now.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture) + ") >>\nendobj\n");
                long xref = ms.Position;
                put("xref\n0 7\n0000000000 65535 f \n");
                for (int i = 1; i <= 6; i++) put(offsets[i].ToString("0000000000", CultureInfo.InvariantCulture) + " 00000 n \n");
                put("trailer\n<< /Size 7 /Root 1 0 R /Info 6 0 R >>\nstartxref\n" + xref + "\n%%EOF\n");
                File.WriteAllBytes(path, ms.ToArray());
            }
        }

        static string PdfString(string s)
        {
            var sb = new StringBuilder();
            foreach (char ch in s)
            {
                if (ch == '(' || ch == ')' || ch == '\\') sb.Append('\\');
                sb.Append(ch < 128 ? ch : '?');
            }
            return sb.ToString();
        }

        /// <summary>Top-to-bottom rows of R, G, B bytes.</summary>
        static byte[] RgbBytes(Bitmap bmp)
        {
            var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
            var data = bmp.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            try
            {
                int rowBytes = bmp.Width * 3;
                var row = new byte[Math.Abs(data.Stride)];
                var outBytes = new byte[rowBytes * bmp.Height];
                for (int y = 0; y < bmp.Height; y++)
                {
                    Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), row, 0, row.Length);
                    int o = y * rowBytes;
                    for (int x = 0; x < bmp.Width; x++)
                    {
                        outBytes[o + x * 3] = row[x * 3 + 2];     // GDI+ stores B, G, R
                        outBytes[o + x * 3 + 1] = row[x * 3 + 1];
                        outBytes[o + x * 3 + 2] = row[x * 3];
                    }
                }
                return outBytes;
            }
            finally { bmp.UnlockBits(data); }
        }

        /// <summary>zlib stream (what PDF's FlateDecode expects): 2-byte header, raw deflate, Adler-32.</summary>
        static byte[] Zlib(byte[] data)
        {
            using (var ms = new MemoryStream())
            {
                ms.WriteByte(0x78); ms.WriteByte(0x9C);
                using (var d = new DeflateStream(ms, CompressionMode.Compress, true)) d.Write(data, 0, data.Length);
                uint a = 1, b = 0;
                foreach (byte x in data) { a = (a + x) % 65521; b = (b + a) % 65521; }
                uint adler = (b << 16) | a;
                ms.WriteByte((byte)(adler >> 24)); ms.WriteByte((byte)(adler >> 16)); ms.WriteByte((byte)(adler >> 8)); ms.WriteByte((byte)adler);
                return ms.ToArray();
            }
        }
    }
}
