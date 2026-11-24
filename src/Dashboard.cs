using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

namespace ScreenRest
{
    // Dashboard: today / 7 days / 30 days at a glance, with summary cards, three charts and short insights
    // worked out from your own stats.csv and breaks.csv. Replaces the plain-text stats, weekly summary and
    // trend windows. Same numbers and insight rules as the Mac app (mac/Sources/Dashboard.swift).

    /// <summary>Totals for a run of days.</summary>
    public class PeriodTotals
    {
        public int Days, Active, EyeT, EyeAll, StrT, StrAll, Postponed, BlurSum, BlurN, EnergySum, EnergyN;

        public PeriodTotals(IEnumerable<DayStats> list)
        {
            foreach (var d in list)
            {
                if (d.ActiveSec > 0 || d.BreaksDue > 0) Days++;
                Active += d.ActiveSec;
                EyeT += d.EyeTaken; EyeAll += d.EyeTaken + d.EyeSkipped;
                StrT += d.StretchTaken; StrAll += d.StretchTaken + d.StretchSkipped;
                Postponed += d.Postponed;
                if (d.EyeBlur > 0) { BlurSum += d.EyeBlur; BlurN++; }
                if (d.Energy > 0) { EnergySum += d.Energy; EnergyN++; }
            }
        }

        public int Due { get { return EyeAll + StrAll; } }
        /// <summary>Share of breaks taken, or null when no break was due.</summary>
        public int? Score { get { return Pct(EyeT + StrT, Due); } }
        public int ActivePerDay { get { return Days == 0 ? 0 : Active / Days; } }
        public double? AvgBlur { get { return BlurN == 0 ? (double?)null : BlurSum / (double)BlurN; } }
        public double? AvgEnergy { get { return EnergyN == 0 ? (double?)null : EnergySum / (double)EnergyN; } }

        public static int? Pct(int a, int b) { return b == 0 ? (int?)null : (int)Math.Round(100.0 * a / b); }
        public static string PctText(int a, int b) { var p = Pct(a, b); return p.HasValue ? p + "%" : "–"; }
    }

    /// <summary>Listed in display order: warnings first so they aren't missed.</summary>
    public enum InsightTone { Watch, Good, Note }

    public class Insight
    {
        public readonly InsightTone Tone;
        public readonly string Text;
        public Insight(InsightTone tone, string text) { Tone = tone; Text = text; }
    }

    public class DashboardModel
    {
        /// <summary>1 = today, 7 or 30 days.</summary>
        public int Range { get; private set; }
        public PeriodTotals Current { get; private set; }
        public PeriodTotals Previous { get; private set; }
        /// <summary>One entry per day the charts show (at least a week), oldest first, with empty days filled in.</summary>
        public readonly List<DayStats> Shown = new List<DayStats>();
        public DateTime ChartStart { get; private set; }
        public readonly int[] HourTaken = new int[24], HourSkipped = new int[24];
        public List<Insight> Insights { get; private set; }

        readonly Func<DayStats> liveToday;
        readonly Func<bool> checkInEnabled;
        List<DayStats> history = new List<DayStats>();
        List<BreakEntry> entries = new List<BreakEntry>();

        public DashboardModel(int range, Func<DayStats> today, Func<bool> checkInEnabled)
        {
            Range = range;
            liveToday = today;
            this.checkInEnabled = checkInEnabled;
            Reload();
        }

        public void Reload() { history = DayStats.History(liveToday()); Recompute(); }
        public void SetRange(int range) { Range = range; Recompute(); }

        public int Span { get { return Shown.Count; } }
        public bool HasRatings { get { foreach (var d in Shown) if (d.EyeBlur > 0 || d.Energy > 0) return true; return false; } }
        public bool HasBreaks { get { foreach (var d in Shown) if (d.BreaksDue > 0) return true; return false; } }
        public bool HasHours { get { for (int h = 0; h < 24; h++) if (HourTaken[h] + HourSkipped[h] > 0) return true; return false; } }

        List<DayStats> Days(int n, int offset)
        {
            var end = DateTime.Today.AddDays(-offset);
            var start = end.AddDays(-(n - 1));
            var list = new List<DayStats>();
            foreach (var d in history) if (d.Date >= start && d.Date <= end) list.Add(d);
            return list;
        }

        void Recompute()
        {
            Current = new PeriodTotals(Days(Range, 0));
            Previous = new PeriodTotals(Days(Range, Range));

            // Charts always show at least a week, so "Today" still has some context.
            int span = Math.Max(7, Range);
            ChartStart = DateTime.Today.AddDays(-(span - 1));
            var byDate = new Dictionary<DateTime, DayStats>();
            foreach (var d in Days(span, 0)) byDate[d.Date] = d;
            Shown.Clear();
            for (int i = 0; i < span; i++)
            {
                var day = ChartStart.AddDays(i);
                DayStats d;
                Shown.Add(byDate.TryGetValue(day, out d) ? d : new DayStats { Date = day });
            }

            entries = new List<BreakEntry>();
            foreach (var e in BreakLog.Load(DateTime.Today.AddDays(-(Range - 1))))
                if (e.Result != BreakResult.Postponed) entries.Add(e);
            Array.Clear(HourTaken, 0, 24);
            Array.Clear(HourSkipped, 0, 24);
            foreach (var e in entries)
                if (e.Result == BreakResult.Completed) HourTaken[e.Time.Hour]++; else HourSkipped[e.Time.Hour]++;

            Insights = MakeInsights();
        }

        public string PeriodName
        {
            get
            {
                if (Range == 1) return L.T("yesterday", "kahapon");
                if (Range == 7) return L.T("the previous 7 days", "nakaraang 7 araw");
                return L.T("the previous 30 days", "nakaraang 30 araw");
            }
        }

        static double Avg(List<int> v, int from, int count)
        {
            double sum = 0;
            for (int i = from; i < from + count; i++) sum += v[i];
            return sum / count;
        }

        List<Insight> MakeInsights()
        {
            var output = new List<Insight>();
            var cur = Current;

            // 1. Break score against the previous period
            if (cur.Score.HasValue && Previous.Score.HasValue)
            {
                int s = cur.Score.Value, d = s - Previous.Score.Value;
                if (d >= 5)
                    output.Add(new Insight(InsightTone.Good, string.Format(L.T("You took more of your breaks: {0}%, up {1} points on {2}.",
                        "Mas marami kang breaks na ginawa: {0}%, tumaas nang {1} puntos kumpara sa {2}."), s, d, PeriodName)));
                else if (d <= -5)
                    output.Add(new Insight(InsightTone.Watch, string.Format(L.T("Your break score slipped to {0}%, down {1} points on {2}. Strict mode can help.",
                        "Bumaba ang break score sa {0}%, {1} puntos mula sa {2}. Makakatulong ang strict mode."), s, -d, PeriodName)));
                else
                    output.Add(new Insight(InsightTone.Note, string.Format(L.T("Steady: you took {0}% of your breaks, about the same as {1}.",
                        "Tuloy-tuloy: {0}% ng breaks ang ginawa mo, halos kapareho ng {1}."), s, PeriodName)));
            }

            // 2. Streak of good days (only days with breaks due count; weekends don't break it)
            int streak = 0;
            for (int i = history.Count - 1; i >= 0; i--)
            {
                var d = history[i];
                if (d.BreaksDue == 0) continue;
                if (d.Score >= 80) streak++; else break;
            }
            if (streak >= 2)
                output.Add(new Insight(InsightTone.Good, string.Format(L.T("{0} workdays in a row with at least 80% of breaks taken.",
                    "{0} sunod-sunod na araw ng trabaho na hindi bababa sa 80% ng breaks ang ginawa."), streak)));

            // 3. Energy on good-break days vs other days (last 30 days of check-ins)
            int hiN = 0, loN = 0; double hiSum = 0, loSum = 0;
            foreach (var d in Days(30, 0))
            {
                if (d.Energy <= 0 || d.BreaksDue == 0) continue;
                if (d.Score >= 80) { hiN++; hiSum += d.Energy; } else { loN++; loSum += d.Energy; }
            }
            if (hiN >= 2 && loN >= 2 && hiSum / hiN - loSum / loN >= 0.3)
                output.Add(new Insight(InsightTone.Good, string.Format(L.T("On days you take most of your breaks, your energy averages {0:0.0}, against {1:0.0} on other days.",
                    "Sa mga araw na ginagawa mo ang karamihan ng breaks, {0:0.0} ang karaniwang lakas mo, kumpara sa {1:0.0} sa ibang araw."), hiSum / hiN, loSum / loN)));

            // 4. Eye blur moving (first half vs second half of the period's ratings)
            var blurs = new List<int>();
            foreach (var d in Days(Math.Max(7, Range), 0)) if (d.EyeBlur > 0) blurs.Add(d.EyeBlur);
            if (blurs.Count >= 4)
            {
                int half = blurs.Count / 2;
                double a = Avg(blurs, 0, half), b = Avg(blurs, half, blurs.Count - half);
                if (b - a >= 0.5)
                    output.Add(new Insight(InsightTone.Watch, L.T("Eye blur has been creeping up. If it stays that way, book an eye exam.",
                        "Unti-unting lumalabo ang mata. Kung magpatuloy, magpa-eye exam ka.")));
                else if (a - b >= 0.5)
                    output.Add(new Insight(InsightTone.Good, L.T("Eye blur is easing off lately. Keep resting those eyes.",
                        "Bumubuti ang labo ng mata nitong huli. Ituloy ang pagpapahinga ng mata.")));
            }

            // 5. Which kind of break gets skipped
            if (cur.EyeAll >= 5 && cur.StrAll >= 3)
            {
                int eyeSkip = 100 * (cur.EyeAll - cur.EyeT) / cur.EyeAll;
                int strSkip = 100 * (cur.StrAll - cur.StrT) / cur.StrAll;
                if (strSkip >= 25 && strSkip - eyeSkip >= 10)
                    output.Add(new Insight(InsightTone.Watch, string.Format(L.T("You skip stretch breaks more than eye breaks ({0}% vs {1}%). A shorter stretch break might be easier to keep.",
                        "Mas madalas mong laktawan ang stretch break kaysa eye break ({0}% vs {1}%). Baka mas madaling sundin ang mas maikling stretch break."), strSkip, eyeSkip)));
                else if (eyeSkip >= 25 && eyeSkip - strSkip >= 10)
                    output.Add(new Insight(InsightTone.Watch, string.Format(L.T("Eye breaks get skipped most ({0}%). They only take 20 seconds: try looking out of a window.",
                        "Eye break ang pinakamadalas laktawan ({0}%). 20 segundo lang ito: subukang tumingin sa bintana."), eyeSkip)));
            }

            // 6. Time of day with the most skipped breaks (from breaks.csv)
            if (entries.Count >= 12)
            {
                int skipped = 0;
                foreach (var e in entries) if (e.Result == BreakResult.Skipped) skipped++;
                double overall = skipped / (double)entries.Count;
                int worst = -1; double worstRate = 0;
                for (int h = 0; h < 24; h++)
                {
                    int n = HourTaken[h] + HourSkipped[h];
                    if (n < 4) continue;
                    double rate = HourSkipped[h] / (double)n;
                    if (worst < 0 || rate > worstRate) { worst = h; worstRate = rate; }
                }
                if (worst >= 0 && worstRate >= 0.3 && worstRate - overall >= 0.15)
                    output.Add(new Insight(InsightTone.Watch, string.Format(L.T("Breaks around {0}:00 get skipped most ({1}%). A heads-up a little earlier may help then.",
                        "Pinakamadalas laktawan ang break bandang {0}:00 ({1}%). Makakatulong ang mas maagang paalala sa oras na iyon."),
                        worst, (int)Math.Round(worstRate * 100))));
            }

            // 7. Postponing habit
            if (cur.Days > 0 && cur.Postponed / (double)cur.Days >= 2)
                output.Add(new Insight(InsightTone.Note, string.Format(L.T("You postpone about {0} breaks a day. A longer heads-up in Settings gives you time to wrap up first.",
                    "Mga {0} break bawat araw ang ipinagpapaliban mo. Bigyan ang sarili ng mas mahabang paalala sa Settings."),
                    (int)Math.Round(cur.Postponed / (double)cur.Days))));

            // 8. Long screen days
            if (Range > 1 && cur.Days >= 2 && cur.ActivePerDay >= 7 * 3600)
                output.Add(new Insight(InsightTone.Note, string.Format(L.T("You average {0} of active screen time a day. Breaks matter most on days like these.",
                    "Karaniwang {0} ang aktibong oras mo sa screen bawat araw. Pinakamahalaga ang breaks sa ganitong mga araw."),
                    DayStats.Duration(cur.ActivePerDay))));

            // 9. Nudge to do the check-in
            if (checkInEnabled() && cur.BlurN == 0 && cur.EnergyN == 0 && cur.Days > 0)
                output.Add(new Insight(InsightTone.Note, L.T("Do the end-of-shift check-in to see how breaks affect your eyes and energy.",
                    "Gawin ang check-in sa dulo ng shift para makita kung paano nakakaapekto ang breaks sa mata at lakas mo.")));

            if (output.Count == 0)
                output.Add(new Insight(InsightTone.Note, L.T("Insights appear here after a day or two of breaks.",
                    "Lalabas dito ang mga obserbasyon pagkatapos ng isa o dalawang araw ng breaks.")));

            // Keep it short: at most four, warnings first.
            var sorted = new List<Insight>();
            foreach (InsightTone t in new[] { InsightTone.Watch, InsightTone.Good, InsightTone.Note })
                foreach (var i in output) if (i.Tone == t && sorted.Count < 4) sorted.Add(i);
            return sorted;
        }
    }

    /// <summary>Drawing shared by the Dashboard window and the PDF report. Sizes are in 96-dpi pixels times k.</summary>
    public static class DashPaint
    {
        public static readonly Color Teal = IconFactory.Brand;
        public static readonly Color Blue = Color.FromArgb(70, 120, 210);
        public static readonly Color SkipGray = Color.FromArgb(206, 213, 219);
        public static readonly Color BlurColor = Color.FromArgb(232, 120, 40);
        public static readonly Color EnergyColor = Color.FromArgb(46, 160, 80);
        public static readonly Color Good = Color.FromArgb(36, 150, 80);
        public static readonly Color Watch = Color.FromArgb(222, 115, 30);
        public static readonly Color Ink = Color.FromArgb(20, 30, 36);
        public static readonly Color Ink2 = Color.FromArgb(96, 108, 118);
        public static readonly Color Border = Color.FromArgb(224, 230, 234);
        public static readonly Color GridLine = Color.FromArgb(234, 238, 241);
        public static readonly Color PageBg = Color.FromArgb(243, 246, 247);

        public static string EyeLabel { get { return L.T("Eye breaks", "Eye breaks"); } }
        public static string StretchLabel { get { return L.T("Stretch breaks", "Stretch breaks"); } }
        public static string SkippedLabel { get { return L.T("Skipped", "Nilaktawan"); } }
        public static string TakenLabel { get { return L.T("Taken", "Ginawa"); } }
        public static string BlurLabel { get { return L.T("Eye blur", "Labo ng mata"); } }
        public static string EnergyLabel { get { return L.T("Energy", "Lakas"); } }

        public static GraphicsPath Rounded(RectangleF r, float radius)
        {
            var p = new GraphicsPath();
            float d = radius * 2;
            p.AddArc(r.Left, r.Top, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Top, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.Left, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static void Card(Graphics g, RectangleF r, float k)
        {
            using (var path = Rounded(r, 10 * k))
            using (var pen = new Pen(Border, Math.Max(1, k)))
            {
                g.FillPath(Brushes.White, path);
                g.DrawPath(pen, path);
            }
        }

        public static void Text(Graphics g, string s, Font f, Color c, float x, float y)
        {
            using (var b = new SolidBrush(c)) g.DrawString(s, f, b, x, y, StringFormat.GenericTypographic);
        }

        /// <summary>Wrapped text in a column; returns its height.</summary>
        public static float Wrapped(Graphics g, string s, Font f, Color c, float x, float y, float width)
        {
            var size = g.MeasureString(s, f, (int)width);
            using (var b = new SolidBrush(c)) g.DrawString(s, f, b, new RectangleF(x, y, width, size.Height + 2));
            return size.Height;
        }

        static void Centered(Graphics g, string s, Font f, Color c, float cx, float y)
        {
            var w = g.MeasureString(s, f, PointF.Empty, StringFormat.GenericTypographic).Width;
            Text(g, s, f, c, cx - w / 2, y);
        }

        static void RightAligned(Graphics g, string s, Font f, Color c, float right, float y)
        {
            var w = g.MeasureString(s, f, PointF.Empty, StringFormat.GenericTypographic).Width;
            Text(g, s, f, c, right - w, y);
        }

        /// <summary>A row of colour swatches with labels.</summary>
        public static void Legend(Graphics g, float x, float y, Font f, float k, Color[] colors, string[] labels)
        {
            for (int i = 0; i < colors.Length; i++)
            {
                using (var b = new SolidBrush(colors[i])) g.FillEllipse(b, x, y + 3 * k, 9 * k, 9 * k);
                Text(g, labels[i], f, Ink2, x + 13 * k, y);
                x += 13 * k + g.MeasureString(labels[i], f, PointF.Empty, StringFormat.GenericTypographic).Width + 16 * k;
            }
        }

        static int NiceStep(int max)
        {
            if (max <= 4) return 1;
            if (max <= 10) return 2;
            if (max <= 25) return 5;
            if (max <= 50) return 10;
            return 20;
        }

        static string DayLabel(DashboardModel m, DateTime d) { return L.Date(d, m.Span >= 30 ? "d MMM" : "ddd"); }

        static void DayAxis(Graphics g, RectangleF plot, DashboardModel m, Font f, float k)
        {
            float slot = plot.Width / m.Span;
            int every = m.Span >= 30 ? 5 : 1;
            for (int i = 0; i < m.Span; i += every)
                Centered(g, DayLabel(m, m.Shown[i].Date), f, Ink2, plot.Left + slot * (i + 0.5f), plot.Bottom + 5 * k);
        }

        static void Empty(Graphics g, RectangleF r, string text, Font f)
        {
            using (var b = new SolidBrush(Ink2)) g.DrawString(text, f, b, r);
        }

        /// <summary>Stacked bars per day: eye breaks taken, stretch breaks taken, skipped.</summary>
        public static void BreaksChart(Graphics g, RectangleF r, DashboardModel m, Font f, float k)
        {
            if (!m.HasBreaks) { Empty(g, r, L.T("No breaks yet in this period.", "Wala pang breaks sa panahong ito."), f); return; }
            Legend(g, r.Left, r.Top, f, k, new[] { Teal, Blue, SkipGray }, new[] { EyeLabel, StretchLabel, SkippedLabel });
            var plot = new RectangleF(r.Left + 26 * k, r.Top + 26 * k, r.Width - 26 * k, r.Height - 26 * k - 22 * k);
            int max = 1;
            foreach (var d in m.Shown) max = Math.Max(max, d.BreaksDue);
            int step = NiceStep(max), top = (max + step - 1) / step * step;
            using (var pen = new Pen(GridLine, Math.Max(1, k)))
                for (int v = 0; v <= top; v += step)
                {
                    float y = plot.Bottom - plot.Height * v / top;
                    g.DrawLine(pen, plot.Left, y, plot.Right, y);
                    RightAligned(g, v.ToString(), f, Ink2, plot.Left - 6 * k, y - f.GetHeight(g) / 2);
                }
            float slot = plot.Width / m.Span, bw = Math.Min(slot * 0.62f, 34 * k);
            using (var eye = new SolidBrush(Teal))
            using (var str = new SolidBrush(Blue))
            using (var skip = new SolidBrush(SkipGray))
                for (int i = 0; i < m.Span; i++)
                {
                    var d = m.Shown[i];
                    float x = plot.Left + slot * i + (slot - bw) / 2, y = plot.Bottom;
                    foreach (var part in new[] { new KeyValuePair<int, Brush>(d.EyeTaken, eye),
                                                 new KeyValuePair<int, Brush>(d.StretchTaken, str),
                                                 new KeyValuePair<int, Brush>(d.EyeSkipped + d.StretchSkipped, skip) })
                    {
                        if (part.Key <= 0) continue;
                        float h = plot.Height * part.Key / top;
                        g.FillRectangle(part.Value, x, y - h, bw, h);
                        y -= h;
                    }
                }
            DayAxis(g, plot, m, f, k);
        }

        /// <summary>Eye blur and energy check-ins (1-5) as two lines.</summary>
        public static void RatingsChart(Graphics g, RectangleF r, DashboardModel m, Font f, float k)
        {
            Legend(g, r.Left, r.Top, f, k, new[] { BlurColor, EnergyColor }, new[] { BlurLabel, EnergyLabel });
            var plot = new RectangleF(r.Left + 26 * k, r.Top + 30 * k, r.Width - 26 * k, r.Height - 30 * k - 22 * k);
            using (var pen = new Pen(GridLine, Math.Max(1, k)))
                for (int v = 1; v <= 5; v++)
                {
                    float y = RatingY(plot, v);
                    g.DrawLine(pen, plot.Left, y, plot.Right, y);
                    RightAligned(g, v.ToString(), f, Ink2, plot.Left - 6 * k, y - f.GetHeight(g) / 2);
                }
            RatingLine(g, plot, m, BlurColor, true, k);
            RatingLine(g, plot, m, EnergyColor, false, k);
            DayAxis(g, plot, m, f, k);
        }

        static float RatingY(RectangleF plot, int v) { return plot.Bottom - plot.Height * (v - 1) / 4f; }

        static void RatingLine(Graphics g, RectangleF plot, DashboardModel m, Color c, bool blur, float k)
        {
            float slot = plot.Width / m.Span;
            var pts = new List<PointF>();
            for (int i = 0; i < m.Span; i++)
            {
                int v = blur ? m.Shown[i].EyeBlur : m.Shown[i].Energy;
                if (v > 0) pts.Add(new PointF(plot.Left + slot * (i + 0.5f), RatingY(plot, v)));
            }
            using (var pen = new Pen(c, 2.4f * k))
            using (var b = new SolidBrush(c))
            {
                if (pts.Count > 1) g.DrawLines(pen, pts.ToArray());
                float dot = 7 * k;
                foreach (var p in pts) g.FillEllipse(b, p.X - dot / 2, p.Y - dot / 2, dot, dot);
            }
        }

        /// <summary>Breaks taken and skipped by hour of day (from breaks.csv).</summary>
        public static void HoursChart(Graphics g, RectangleF r, DashboardModel m, Font f, float k)
        {
            if (!m.HasHours)
            {
                Empty(g, r, L.T("Shows when you take or skip breaks, once a few breaks are logged with this version.",
                    "Ipinapakita kung kailan mo ginagawa o nilalaktawan ang breaks, kapag may ilang break nang naitala sa bersyong ito."), f);
                return;
            }
            Legend(g, r.Left, r.Top, f, k, new[] { Teal, SkipGray }, new[] { TakenLabel, SkippedLabel });
            int first = 23, last = 0, max = 1;
            for (int h = 0; h < 24; h++)
            {
                int n = m.HourTaken[h] + m.HourSkipped[h];
                if (n == 0) continue;
                first = Math.Min(first, h); last = Math.Max(last, h); max = Math.Max(max, n);
            }
            var plot = new RectangleF(r.Left + 26 * k, r.Top + 26 * k, r.Width - 26 * k, r.Height - 26 * k - 22 * k);
            int step = NiceStep(max), top = (max + step - 1) / step * step;
            using (var pen = new Pen(GridLine, Math.Max(1, k)))
                for (int v = 0; v <= top; v += step)
                {
                    float y = plot.Bottom - plot.Height * v / top;
                    g.DrawLine(pen, plot.Left, y, plot.Right, y);
                    RightAligned(g, v.ToString(), f, Ink2, plot.Left - 6 * k, y - f.GetHeight(g) / 2);
                }
            int count = last - first + 1, every = count > 12 ? 2 : 1;
            float slot = plot.Width / count, bw = Math.Min(slot * 0.62f, 34 * k);
            using (var taken = new SolidBrush(Teal))
            using (var skip = new SolidBrush(SkipGray))
                for (int i = 0; i < count; i++)
                {
                    int h = first + i;
                    float x = plot.Left + slot * i + (slot - bw) / 2;
                    float ht = plot.Height * m.HourTaken[h] / top, hs = plot.Height * m.HourSkipped[h] / top;
                    if (ht > 0) g.FillRectangle(taken, x, plot.Bottom - ht, bw, ht);
                    if (hs > 0) g.FillRectangle(skip, x, plot.Bottom - ht - hs, bw, hs);
                    if (i % every == 0) Centered(g, h + ":00", f, Ink2, x + bw / 2, plot.Bottom + 5 * k);
                }
        }

        /// <summary>Small round badge for an insight: tick (good), exclamation mark (watch) or "i" (note).</summary>
        public static void InsightBadge(Graphics g, InsightTone tone, float x, float y, float k)
        {
            float d = 18 * k;
            using (var b = new SolidBrush(tone == InsightTone.Good ? Good : tone == InsightTone.Watch ? Watch : Teal))
                g.FillEllipse(b, x, y, d, d);
            using (var pen = new Pen(Color.White, 2f * k) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
            using (var dot = new SolidBrush(Color.White))
            {
                float cx = x + d / 2, cy = y + d / 2;
                if (tone == InsightTone.Good)
                    g.DrawLines(pen, new[] { new PointF(cx - 4.5f * k, cy + 0.2f * k), new PointF(cx - 1.2f * k, cy + 3.4f * k), new PointF(cx + 4.6f * k, cy - 3.4f * k) });
                else if (tone == InsightTone.Watch)
                {
                    g.DrawLine(pen, cx, cy - 4.5f * k, cx, cy + 0.8f * k);
                    g.FillEllipse(dot, cx - 1.3f * k, cy + 3f * k, 2.6f * k, 2.6f * k);
                }
                else
                {
                    g.FillEllipse(dot, cx - 1.3f * k, cy - 5.2f * k, 2.6f * k, 2.6f * k);
                    g.DrawLine(pen, cx, cy - 0.8f * k, cx, cy + 4.5f * k);
                }
            }
        }

        public static void ScoreRing(Graphics g, int? score, float x, float y, float size, Font f, float k)
        {
            float w = 9 * k;
            var r = new RectangleF(x + w / 2, y + w / 2, size - w, size - w);
            using (var bg = new Pen(Color.FromArgb(228, 233, 237), w))
                g.DrawEllipse(bg, r);
            if (score.HasValue && score.Value > 0)
                using (var fg = new Pen(Teal, w) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                    g.DrawArc(fg, r, -90, 360f * Math.Min(100, score.Value) / 100f);
            string t = score.HasValue ? score + "%" : "–";
            var sz = g.MeasureString(t, f, PointF.Empty, StringFormat.GenericTypographic);
            Text(g, t, f, Ink, x + (size - sz.Width) / 2, y + (size - sz.Height) / 2);
        }
    }

    /// <summary>The Dashboard window (tray menu > Dashboard..., or double-click the tray icon).</summary>
    public class DashboardForm : Form
    {
        readonly DashboardModel model;
        readonly Func<DayStats> today;
        readonly Canvas canvas;
        readonly Button[] rangeButtons = new Button[3];
        readonly int[] ranges = { 1, 7, 30 };
        readonly Label lblCompare;
        readonly Timer refresh;

        public DashboardForm(int range, Func<DayStats> today, Func<bool> checkInEnabled, Action onCheckIn)
        {
            this.today = today;
            model = new DashboardModel(range, today, checkInEnabled);
            Text = L.T("ScreenRest Dashboard", "ScreenRest Dashboard");
            Icon = IconFactory.MakeIcon(IconFactory.Brand);
            StartPosition = FormStartPosition.CenterScreen;
            Font = new Font("Segoe UI", 9.5f);
            BackColor = DashPaint.PageBg;
            float k = DeviceScale();
            Size = new Size((int)(1060 * k), (int)(820 * k));
            MinimumSize = new Size((int)(880 * k), (int)(600 * k));

            // Header: title and date on the left, Today / 7 days / 30 days on the right.
            var header = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2, Padding = new Padding((int)(20 * k), (int)(14 * k), (int)(20 * k), (int)(4 * k)), BackColor = DashPaint.PageBg };
            header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            var titles = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false, Margin = new Padding(0) };
            titles.Controls.Add(new Label { Text = L.T("Dashboard", "Dashboard"), AutoSize = true, Font = new Font("Segoe UI Semibold", 20f), ForeColor = DashPaint.Ink, Margin = new Padding(0) });
            titles.Controls.Add(new Label
            {
                Text = L.Date(DateTime.Today, "dddd d MMMM") + (DayStats.DemoMode ? L.T(" · demo stats", " · demo stats") : ""),
                AutoSize = true, ForeColor = DashPaint.Ink2, Margin = new Padding(2, 0, 0, 0)
            });
            header.Controls.Add(titles, 0, 0);
            var picker = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Anchor = AnchorStyles.Right, Margin = new Padding(0) };
            string[] names = { L.T("Today", "Ngayon"), L.T("7 days", "7 araw"), L.T("30 days", "30 araw") };
            for (int i = 0; i < 3; i++)
            {
                int r = ranges[i];
                var b = new Button { Text = names[i], AutoSize = true, FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand, Margin = new Padding(0), Padding = new Padding((int)(10 * k), (int)(3 * k), (int)(10 * k), (int)(3 * k)) };
                b.FlatAppearance.BorderColor = DashPaint.Border;
                b.Click += (o, e) => SetRange(r);
                rangeButtons[i] = b;
                picker.Controls.Add(b);
            }
            header.Controls.Add(picker, 1, 0);

            // Footer: what the numbers are compared with, and the actions.
            var footer = new TableLayoutPanel { Dock = DockStyle.Bottom, AutoSize = true, ColumnCount = 2, Padding = new Padding((int)(20 * k), (int)(8 * k), (int)(20 * k), (int)(12 * k)), BackColor = DashPaint.PageBg };
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            lblCompare = new Label { AutoSize = true, ForeColor = DashPaint.Ink2, Anchor = AnchorStyles.Left, Margin = new Padding(0) };
            footer.Controls.Add(lblCompare, 0, 0);
            var actions = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Anchor = AnchorStyles.Right, Margin = new Padding(0) };
            var checkIn = new Button { Text = L.T("Daily check-in...", "Check-in..."), AutoSize = true, Padding = new Padding((int)(6 * k), (int)(2 * k), (int)(6 * k), (int)(2 * k)) };
            checkIn.Click += (o, e) => onCheckIn();
            var folder = new Button { Text = L.T("Open data folder", "Buksan ang data folder"), AutoSize = true, Padding = checkIn.Padding };
            folder.Click += (o, e) => { try { Process.Start("explorer.exe", DayStats.DataFolder); } catch { } };
            var pdf = new Button
            {
                Text = L.T("Export PDF for my doctor...", "I-export ang PDF para sa doktor..."), AutoSize = true, Padding = checkIn.Padding,
                FlatStyle = FlatStyle.Flat, BackColor = DashPaint.Teal, ForeColor = Color.White, Font = new Font("Segoe UI Semibold", 9.5f), Cursor = Cursors.Hand
            };
            pdf.FlatAppearance.BorderColor = DashPaint.Teal;
            pdf.Click += (o, e) => ReportPdf.ExportWithDialog(this, this.today);
            actions.Controls.AddRange(new Control[] { checkIn, folder, pdf });
            footer.Controls.Add(actions, 1, 0);

            canvas = new Canvas(model) { Dock = DockStyle.Fill };
            Controls.Add(canvas);
            Controls.Add(footer);
            Controls.Add(header);

            refresh = new Timer { Interval = 30000 };
            refresh.Tick += (o, e) => Reload();
            refresh.Start();
            Activated += (o, e) => Reload();
            FormClosed += (o, e) => refresh.Dispose();
            UpdateRangeUi();
        }

        float DeviceScale()
        {
            using (var g = CreateGraphics()) return g.DpiX / 96f;
        }

        /// <summary>Brings the window forward on the given range (1, 7 or 30 days).</summary>
        public void ShowRange(int range)
        {
            SetRange(range);
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            Activate();
        }

        public void Reload()
        {
            model.Reload();
            UpdateRangeUi();
        }

        void SetRange(int range)
        {
            if (range != model.Range) { model.SetRange(range); canvas.AutoScrollPosition = Point.Empty; }
            UpdateRangeUi();
        }

        void UpdateRangeUi()
        {
            for (int i = 0; i < 3; i++)
            {
                bool on = ranges[i] == model.Range;
                rangeButtons[i].BackColor = on ? DashPaint.Teal : Color.White;
                rangeButtons[i].ForeColor = on ? Color.White : DashPaint.Ink;
                rangeButtons[i].FlatAppearance.BorderColor = on ? DashPaint.Teal : DashPaint.Border;
            }
            lblCompare.Text = string.Format(L.T("Compared with {0}.", "Kumpara sa {0}."), model.PeriodName);
            canvas.Relayout();
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            // Tray apps don't own the foreground, so lift the window above others once.
            TopMost = true; TopMost = false;
            Activate();
        }

        /// <summary>Scrollable surface that paints the cards and charts.</summary>
        class Canvas : Panel
        {
            readonly DashboardModel m;

            public Canvas(DashboardModel model)
            {
                m = model;
                AutoScroll = true;
                SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
                BackColor = DashPaint.PageBg;
            }

            protected override void OnScroll(ScrollEventArgs se) { base.OnScroll(se); Invalidate(); }
            protected override void OnMouseWheel(MouseEventArgs e) { base.OnMouseWheel(e); Invalidate(); }

            protected override void OnPaint(PaintEventArgs e)
            {
                var g = e.Graphics;
                g.TranslateTransform(AutoScrollPosition.X, AutoScrollPosition.Y);
                SetHeight(Render(g));
            }

            protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); Relayout(); }
            protected override void OnResize(EventArgs eventargs) { base.OnResize(eventargs); if (IsHandleCreated) Relayout(); }

            /// <summary>Works out the content height (for the scroll bar) off screen, then repaints.</summary>
            public void Relayout()
            {
                if (IsHandleCreated)
                {
                    float dpi;
                    using (var sg = CreateGraphics()) dpi = sg.DpiX;
                    using (var bmp = new Bitmap(1, 1))
                    {
                        bmp.SetResolution(dpi, dpi);
                        using (var g = Graphics.FromImage(bmp)) SetHeight(Render(g));
                    }
                }
                Invalidate();
            }

            void SetHeight(int height)
            {
                if (AutoScrollMinSize.Height != height) AutoScrollMinSize = new Size(0, height);
            }

            int Render(Graphics g)
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
                float k = g.DpiX / 96f;
                using (var f = new Font("Segoe UI", 9f))
                using (var fHead = new Font("Segoe UI Semibold", 11f))
                using (var fBig = new Font("Segoe UI Semibold", 19f))
                using (var fRing = new Font("Segoe UI Semibold", 13f))
                using (var fBody = new Font("Segoe UI", 10f))
                    return (int)Draw(g, k, ClientSize.Width, f, fHead, fBig, fRing, fBody);
            }

            float Draw(Graphics g, float k, float width, Font f, Font fHead, Font fBig, Font fRing, Font fBody)
            {
                var c = m.Current; var p = m.Previous;
                float pad = 20 * k, gap = 14 * k, W = width - 2 * pad, y = 6 * k;

                // Summary cards
                float cw = (W - 3 * gap) / 4, ch = 112 * k;
                var r0 = new RectangleF(pad, y, cw, ch);
                DashPaint.Card(g, r0, k);
                DashPaint.ScoreRing(g, c.Score, r0.Left + 16 * k, r0.Top + (ch - 66 * k) / 2, 66 * k, fRing, k);
                float tx = r0.Left + 96 * k;
                DashPaint.Text(g, L.T("Break score", "Break score"), fBody, DashPaint.Ink2, tx, r0.Top + 24 * k);
                DashPaint.Text(g, L.T("of breaks taken", "ng breaks ang ginawa"), f, DashPaint.Ink2, tx, r0.Top + 46 * k);
                Delta(g, f, k, tx, r0.Top + 68 * k, Diff(c.Score, p.Score), L.T("pts", "puntos"), true, null);

                Metric(g, k, new RectangleF(pad + (cw + gap), y, cw, ch), f, fBig, fBody,
                    L.T("Screen time", "Oras sa screen"),
                    DayStats.Duration(m.Range == 1 ? c.Active : c.ActivePerDay),
                    m.Range == 1 ? L.T("active so far today", "aktibo hanggang ngayon") : L.T("per workday, on average", "bawat araw ng trabaho, karaniwan"),
                    p.Days == 0 ? (int?)null : (c.ActivePerDay - p.ActivePerDay) / 60, "min", false,
                    m.Range == 1 ? L.T("Day still in progress", "Hindi pa tapos ang araw") : null);
                Metric(g, k, new RectangleF(pad + 2 * (cw + gap), y, cw, ch), f, fBig, fBody,
                    L.T("Eye breaks", "Eye breaks"), c.EyeT + "/" + c.EyeAll, PeriodTotals.PctText(c.EyeT, c.EyeAll) + L.T(" taken", " ginawa"),
                    Diff(PeriodTotals.Pct(c.EyeT, c.EyeAll), PeriodTotals.Pct(p.EyeT, p.EyeAll)), L.T("pts", "puntos"), true, null);
                Metric(g, k, new RectangleF(pad + 3 * (cw + gap), y, cw, ch), f, fBig, fBody,
                    L.T("Stretch breaks", "Stretch breaks"), c.StrT + "/" + c.StrAll, PeriodTotals.PctText(c.StrT, c.StrAll) + L.T(" taken", " ginawa"),
                    Diff(PeriodTotals.Pct(c.StrT, c.StrAll), PeriodTotals.Pct(p.StrT, p.StrAll)), L.T("pts", "puntos"), true, null);
                y += ch + gap;

                // Charts on the left, insights on the right
                float iw = 300 * k, lw = W - iw - gap, ly = y;
                ly = ChartCard(g, k, new RectangleF(pad, ly, lw, 262 * k), fHead, L.T("Breaks per day", "Breaks bawat araw"),
                    inner => DashPaint.BreaksChart(g, inner, m, f, k)) + gap;
                ly = ChartCard(g, k, new RectangleF(pad, ly, lw, 232 * k), fHead, L.T("How you felt (1–5)", "Ang pakiramdam mo (1–5)"), inner =>
                {
                    if (!m.HasRatings)
                        using (var b = new SolidBrush(DashPaint.Ink2))
                            g.DrawString(L.T("No check-ins in this period. Rate your eye blur and energy at the end of a shift (Daily check-in, below) to see a trend here.",
                                "Walang check-in sa panahong ito. I-rate ang labo ng mata at lakas sa dulo ng shift (Check-in, sa ibaba) para makita ang takbo rito."), fBody, b, inner);
                    else
                    {
                        DashPaint.RatingsChart(g, new RectangleF(inner.Left, inner.Top, inner.Width, inner.Height - 22 * k), m, f, k);
                        DashPaint.Text(g, L.T("Eye blur: lower is better. Energy: higher is better.",
                            "Labo ng mata: mas mababa, mas mabuti. Lakas: mas mataas, mas mabuti."), f, DashPaint.Ink2, inner.Left, inner.Bottom - 14 * k);
                    }
                }) + gap;
                ly = ChartCard(g, k, new RectangleF(pad, ly, lw, 212 * k), fHead, L.T("Time of day", "Oras ng araw"),
                    inner => DashPaint.HoursChart(g, inner, m, f, k));

                // Insights card: measure first, then draw
                float ix = pad + lw + gap, textW = iw - 32 * k - 28 * k, ih = 50 * k;
                foreach (var i in m.Insights) ih += g.MeasureString(i.Text, fBody, (int)textW).Height + 14 * k;
                string note = L.T("Worked out on this PC from your own history. A wellness guide, not medical advice.",
                    "Kinuwenta sa PC na ito mula sa sarili mong history. Gabay sa kalusugan, hindi payong medikal.");
                ih += 14 * k + g.MeasureString(note, f, (int)(iw - 32 * k)).Height + 16 * k;
                var ir = new RectangleF(ix, y, iw, ih);
                DashPaint.Card(g, ir, k);
                DashPaint.Text(g, L.T("Insights", "Mga obserbasyon"), fHead, DashPaint.Ink, ir.Left + 16 * k, ir.Top + 14 * k);
                float iy = ir.Top + 50 * k;
                foreach (var i in m.Insights)
                {
                    DashPaint.InsightBadge(g, i.Tone, ir.Left + 16 * k, iy + 1 * k, k);
                    iy += DashPaint.Wrapped(g, i.Text, fBody, DashPaint.Ink, ir.Left + 16 * k + 28 * k, iy, textW) + 14 * k;
                }
                using (var pen = new Pen(DashPaint.Border, Math.Max(1, k))) g.DrawLine(pen, ir.Left + 16 * k, iy, ir.Right - 16 * k, iy);
                DashPaint.Wrapped(g, note, f, DashPaint.Ink2, ir.Left + 16 * k, iy + 12 * k, iw - 32 * k);

                return Math.Max(ly, ir.Bottom) + pad;
            }

            static float ChartCard(Graphics g, float k, RectangleF r, Font fHead, string title, Action<RectangleF> drawInner)
            {
                DashPaint.Card(g, r, k);
                DashPaint.Text(g, title, fHead, DashPaint.Ink, r.Left + 16 * k, r.Top + 14 * k);
                drawInner(new RectangleF(r.Left + 16 * k, r.Top + 46 * k, r.Width - 32 * k, r.Height - 46 * k - 14 * k));
                return r.Bottom;
            }

            static int? Diff(int? a, int? b) { return a.HasValue && b.HasValue ? a.Value - b.Value : (int?)null; }

            static void Metric(Graphics g, float k, RectangleF r, Font f, Font fBig, Font fBody, string title, string value, string detail,
                               int? delta, string unit, bool higherIsBetter, string note)
            {
                DashPaint.Card(g, r, k);
                float x = r.Left + 16 * k;
                DashPaint.Text(g, title, fBody, DashPaint.Ink2, x, r.Top + 12 * k);
                DashPaint.Text(g, value, fBig, DashPaint.Ink, x, r.Top + 32 * k);
                DashPaint.Text(g, detail, f, DashPaint.Ink2, x, r.Top + 70 * k);
                Delta(g, f, k, x, r.Top + 88 * k, delta, unit, higherIsBetter, note);
            }

            /// <summary>Small coloured change line: "▲ +6 pts".</summary>
            static void Delta(Graphics g, Font f, float k, float x, float y, int? v, string unit, bool higherIsBetter, string note)
            {
                if (note != null) { DashPaint.Text(g, note, f, DashPaint.Ink2, x, y); return; }
                if (!v.HasValue) { DashPaint.Text(g, L.T("No earlier data", "Wala pang naunang data"), f, DashPaint.Ink2, x, y); return; }
                int d = v.Value;
                bool good = higherIsBetter ? d > 0 : d < 0;
                var color = d == 0 ? DashPaint.Ink2 : good ? DashPaint.Good : DashPaint.Watch;
                string arrow = d > 0 ? "▲ " : d < 0 ? "▼ " : "= ";
                using (var fb = new Font(f, FontStyle.Bold))
                    DashPaint.Text(g, arrow + (d > 0 ? "+" : "") + d + " " + unit, fb, color, x, y);
            }
        }
    }
}
