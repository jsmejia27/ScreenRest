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
        public int BreaksDue { get { return EyeTaken + EyeSkipped + StretchTaken + StretchSkipped; } }

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
    }
}
