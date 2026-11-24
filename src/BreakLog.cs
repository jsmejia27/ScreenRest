using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace ScreenRest
{
    /// <summary>One break, as logged in breaks.csv.</summary>
    public class BreakEntry
    {
        public DateTime Time;
        public BreakKind Kind;
        public BreakResult Result;
        public int PlannedSec, TakenSec, PausedSec;
    }

    /// <summary>
    /// One row per break in %APPDATA%\ScreenRest\breaks.csv (breaks-demo.csv in --demo mode), next to stats.csv.
    /// stats.csv keeps the daily totals; this file adds the time of each break, so the Dashboard can show
    /// the time of day you take or skip breaks. Same format as the Mac app:
    ///   time,kind,result,planned_sec,taken_sec,paused_sec
    ///   2026-11-24T14:00:12,stretch,completed,300,300,4
    /// </summary>
    public static class BreakLog
    {
        const string Header = "time,kind,result,planned_sec,taken_sec,paused_sec";
        const string TimeFormat = "yyyy-MM-dd'T'HH:mm:ss"; // local time, like the dates in stats.csv

        static string FilePath { get { return Path.Combine(Settings.Dir, DayStats.DemoMode ? "breaks-demo.csv" : "breaks.csv"); } }

        static string Name(BreakResult r)
        {
            return r == BreakResult.Completed ? "completed" : r == BreakResult.Skipped ? "skipped" : "postponed";
        }

        public static void Append(BreakEntry e)
        {
            try
            {
                Directory.CreateDirectory(Settings.Dir);
                string line = string.Join(",", new[] {
                    e.Time.ToString(TimeFormat, CultureInfo.InvariantCulture),
                    e.Kind == BreakKind.Eye ? "eye" : "stretch", Name(e.Result),
                    e.PlannedSec.ToString(CultureInfo.InvariantCulture), e.TakenSec.ToString(CultureInfo.InvariantCulture),
                    e.PausedSec.ToString(CultureInfo.InvariantCulture) }) + "\n";
                if (!File.Exists(FilePath)) line = Header + "\n" + line;
                File.AppendAllText(FilePath, line);
            }
            catch { }
        }

        /// <summary>Entries from <paramref name="since"/> (inclusive) onwards.</summary>
        public static List<BreakEntry> Load(DateTime since)
        {
            var list = new List<BreakEntry>();
            try
            {
                if (!File.Exists(FilePath)) return list;
                foreach (var line in File.ReadAllLines(FilePath))
                {
                    var p = line.Split(',');
                    DateTime t;
                    if (p.Length < 6 || !DateTime.TryParseExact(p[0], TimeFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out t) || t < since) continue;
                    BreakResult r;
                    if (p[2] == "completed") r = BreakResult.Completed;
                    else if (p[2] == "skipped") r = BreakResult.Skipped;
                    else if (p[2] == "postponed") r = BreakResult.Postponed;
                    else continue;
                    var e = new BreakEntry { Time = t, Kind = p[1] == "eye" ? BreakKind.Eye : BreakKind.Stretch, Result = r };
                    int.TryParse(p[3], out e.PlannedSec); int.TryParse(p[4], out e.TakenSec); int.TryParse(p[5], out e.PausedSec);
                    list.Add(e);
                }
            }
            catch { }
            return list;
        }
    }
}
