using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace ScreenRest
{
    /// <summary>One row per day in %APPDATA%\ScreenRest\stats.csv (stats-demo.csv in --demo mode).</summary>
    public class DayStats
    {
        public DateTime Date;
        public int EyeTaken, EyeSkipped, StretchTaken, StretchSkipped, Postponed, ActiveSec;
        public int EyeBlur;  // daily check-in, 1 (clear) .. 5 (very blurry); 0 = not answered
        public int Energy;   // daily check-in, 1 (exhausted) .. 5 (great); 0 = not answered

        /// <summary>Set by --demo so test runs never touch your real history.</summary>
        public static bool DemoMode;

        static string FilePath { get { return Path.Combine(Settings.Dir, DemoMode ? "stats-demo.csv" : "stats.csv"); } }
        const string Header = "date,eye_taken,eye_skipped,stretch_taken,stretch_skipped,postponed,active_sec,eye_blur,energy";

        public int Score
        {
            get
            {
                int total = EyeTaken + EyeSkipped + StretchTaken + StretchSkipped;
                return total == 0 ? 100 : (int)Math.Round(100.0 * (EyeTaken + StretchTaken) / total);
            }
        }
        public bool CheckedIn { get { return EyeBlur > 0 || Energy > 0; } }

        public string ToCsv()
        {
            return string.Join(",", new[] { Date.ToString("yyyy-MM-dd"), EyeTaken.ToString(), EyeSkipped.ToString(),
                StretchTaken.ToString(), StretchSkipped.ToString(), Postponed.ToString(), ActiveSec.ToString(),
                EyeBlur.ToString(), Energy.ToString() });
        }

        static DayStats Parse(string line)
        {
            var p = line.Split(',');
            if (p.Length < 7) return null;
            DateTime d;
            if (!DateTime.TryParseExact(p[0], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out d)) return null;
            var s = new DayStats { Date = d };
            int.TryParse(p[1], out s.EyeTaken); int.TryParse(p[2], out s.EyeSkipped);
            int.TryParse(p[3], out s.StretchTaken); int.TryParse(p[4], out s.StretchSkipped);
            int.TryParse(p[5], out s.Postponed); int.TryParse(p[6], out s.ActiveSec);
            if (p.Length >= 9) { int.TryParse(p[7], out s.EyeBlur); int.TryParse(p[8], out s.Energy); } // older files lack these
            return s;
        }

        public static List<DayStats> LoadAll()
        {
            var list = new List<DayStats>();
            try
            {
                if (File.Exists(FilePath))
                    foreach (var line in File.ReadAllLines(FilePath))
                    {
                        var s = Parse(line);
                        if (s != null) list.Add(s);
                    }
            }
            catch { }
            list.Sort((a, b) => a.Date.CompareTo(b.Date));
            return list;
        }

        public static DayStats LoadToday()
        {
            foreach (var s in LoadAll()) if (s.Date == DateTime.Today) return s;
            return new DayStats { Date = DateTime.Today };
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Settings.Dir);
                var all = LoadAll();
                var sb = new StringBuilder(Header + Environment.NewLine);
                bool written = false;
                foreach (var s in all)
                {
                    if (s.Date == Date) { sb.AppendLine(ToCsv()); written = true; }
                    else sb.AppendLine(s.ToCsv());
                }
                if (!written) sb.AppendLine(ToCsv());
                File.WriteAllText(FilePath, sb.ToString());
            }
            catch { }
        }

        public static string DataFolder { get { return Settings.Dir; } }

        public static string Duration(int sec)
        {
            return string.Format("{0}h {1:00}m", sec / 3600, (sec % 3600) / 60);
        }

        /// <summary>History with today's live numbers swapped in.</summary>
        public static List<DayStats> History(DayStats today)
        {
            var all = LoadAll();
            bool found = false;
            for (int i = 0; i < all.Count; i++) if (all[i].Date == today.Date) { all[i] = today; found = true; }
            if (!found) all.Add(today);
            return all;
        }

        static string Rating(int v) { return v == 0 ? " -" : " " + v; }

        static void Line(StringBuilder sb, string label, int width, string value) { sb.AppendLine((label + ":").PadRight(width) + value); }

        public static string Report(DayStats today)
        {
            var sb = new StringBuilder();
            if (DemoMode) sb.AppendLine(L.T("(demo mode: separate test stats)", "(demo mode: hiwalay na test stats)")).AppendLine();
            sb.AppendLine(L.T("TODAY", "NGAYONG ARAW") + "  (" + L.Date(today.Date, "ddd d MMM") + ")");
            string taken = L.T(" taken, ", " ginawa, "), skipped = L.T(" skipped", " nilaktawan");
            Line(sb, L.T("Active screen time", "Oras sa screen"), 21, Duration(today.ActiveSec));
            Line(sb, "Eye breaks", 21, today.EyeTaken + taken + today.EyeSkipped + skipped);
            Line(sb, "Stretch breaks", 21, today.StretchTaken + taken + today.StretchSkipped + skipped);
            Line(sb, L.T("Postponed", "Ipinagpaliban"), 21, today.Postponed.ToString());
            Line(sb, "Break score", 21, today.Score + "%");
            Line(sb, "Check-in", 21, today.CheckedIn
                ? string.Format(L.T("eye blur {0}/5, energy {1}/5", "labo ng mata {0}/5, lakas {1}/5"), today.EyeBlur, today.Energy)
                : L.T("not done yet", "hindi pa nagagawa"));
            sb.AppendLine();
            sb.AppendLine(L.T("LAST 14 DAYS                               blur energy",
                              "HULING 14 ARAW                             labo lakas"));
            var all = History(today);
            all.Reverse();
            int n = 0;
            foreach (var row in all)
            {
                sb.AppendLine(string.Format("{0,-11} {1}  eye {2,2}/{3,-2} str {4,2}/{5,-2} {6,3}%  {7}   {8}",
                    L.Date(row.Date, "ddd d MMM"), Duration(row.ActiveSec),
                    row.EyeTaken, row.EyeTaken + row.EyeSkipped, row.StretchTaken, row.StretchTaken + row.StretchSkipped,
                    row.Score, Rating(row.EyeBlur), Rating(row.Energy)));
                if (++n >= 14) break;
            }
            return sb.ToString();
        }

        // ------------------------------------------------------------------ weekly summary
        static DateTime WeekStart(DateTime d)
        {
            int diff = ((int)d.DayOfWeek + 6) % 7; // Monday = 0
            return d.Date.AddDays(-diff);
        }

        class WeekTotals
        {
            public int Days, Active, EyeT, EyeAll, StrT, StrAll, BlurSum, BlurN, EnergySum, EnergyN;
            public DayStats Best;
            public int Score { get { int all = EyeAll + StrAll; return all == 0 ? 0 : (int)Math.Round(100.0 * (EyeT + StrT) / all); } }
            public string AvgBlur { get { return BlurN == 0 ? "-" : (BlurSum / (double)BlurN).ToString("0.0"); } }
            public string AvgEnergy { get { return EnergyN == 0 ? "-" : (EnergySum / (double)EnergyN).ToString("0.0"); } }
        }

        static WeekTotals Totals(List<DayStats> all, DateTime start)
        {
            var w = new WeekTotals();
            foreach (var d in all)
            {
                if (d.Date < start || d.Date >= start.AddDays(7)) continue;
                if (d.ActiveSec > 0) w.Days++;
                w.Active += d.ActiveSec;
                w.EyeT += d.EyeTaken; w.EyeAll += d.EyeTaken + d.EyeSkipped;
                w.StrT += d.StretchTaken; w.StrAll += d.StretchTaken + d.StretchSkipped;
                if (d.EyeBlur > 0) { w.BlurSum += d.EyeBlur; w.BlurN++; }
                if (d.Energy > 0) { w.EnergySum += d.Energy; w.EnergyN++; }
                if (d.ActiveSec > 0 && (w.Best == null || d.Score > w.Best.Score)) w.Best = d;
            }
            return w;
        }

        public static string WeeklyReport(DayStats today)
        {
            var all = History(today);
            var thisStart = WeekStart(today.Date);
            var t = Totals(all, thisStart);
            var l = Totals(all, thisStart.AddDays(-7));
            var sb = new StringBuilder();
            const string F = "{0,-25}{1,9}   {2,9}";
            sb.AppendLine(string.Format(F, L.T("WEEK OF ", "LINGGO NG ") + L.Date(thisStart, "d MMM"),
                L.T("this week", "ngayon"), L.T("last week", "nakaraan")));
            sb.AppendLine(string.Format(F, L.T("Days tracked", "Araw na naitala"), t.Days, l.Days));
            sb.AppendLine(string.Format(F, L.T("Active screen time", "Oras sa screen"), Duration(t.Active), Duration(l.Active)));
            sb.AppendLine(string.Format(F, L.T("Eye breaks taken", "Eye breaks na ginawa"), t.EyeT + "/" + t.EyeAll, l.EyeT + "/" + l.EyeAll));
            sb.AppendLine(string.Format(F, L.T("Stretch breaks taken", "Stretch breaks na ginawa"), t.StrT + "/" + t.StrAll, l.StrT + "/" + l.StrAll));
            sb.AppendLine(string.Format(F, "Break score", t.Score + "%", l.Score + "%"));
            sb.AppendLine(string.Format(F, L.T("Avg right-eye blur (1-5)", "Labo ng kanang mata (1-5)"), t.AvgBlur, l.AvgBlur));
            sb.AppendLine(string.Format(F, L.T("Avg energy (1-5)", "Karaniwang lakas (1-5)"), t.AvgEnergy, l.AvgEnergy));
            sb.AppendLine();
            if (t.Best != null) sb.AppendLine(string.Format(L.T("Best day: {0} ({1}% of breaks taken)", "Pinakamagandang araw: {0} ({1}% ng breaks ang ginawa)"),
                L.Date(t.Best.Date, "dddd"), t.Best.Score));
            if (l.Days > 0 && t.Score > l.Score) sb.AppendLine(L.T("You took more of your breaks than last week. Nice!",
                "Mas marami kang breaks na ginawa kaysa noong nakaraang linggo. Galing!"));
            else if (l.Days > 0 && t.Score < l.Score) sb.AppendLine(L.T("Fewer breaks than last week. Try strict mode next week?",
                "Mas kaunti ang breaks kaysa noong nakaraang linggo. Subukan ang strict mode sa susunod na linggo?"));
            if (t.BlurN > 0 && l.BlurN > 0)
            {
                double tb = t.BlurSum / (double)t.BlurN, lb = l.BlurSum / (double)l.BlurN;
                if (tb > lb + 0.4) sb.AppendLine(L.T("Eye blur is up on last week. Please book that eye exam.",
                    "Lumabo ang mata kumpara noong nakaraang linggo. Magpa-eye exam ka na."));
                else if (tb < lb - 0.4) sb.AppendLine(L.T("Eye blur is down on last week. Keep resting those eyes.",
                    "Bumuti ang labo ng mata kumpara noong nakaraang linggo. Ituloy ang pagpapahinga ng mata."));
            }
            return sb.ToString();
        }
    }
}
