using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.Win32;

namespace ScreenRest
{
    /// <summary>All user settings, persisted to %APPDATA%\ScreenRest\settings.ini</summary>
    public class Settings
    {
        // Shift (minutes after midnight)
        public int ShiftStartMin = 8 * 60;
        public int ShiftEndMin = 17 * 60;
        public bool[] WorkDays = { false, true, true, true, true, true, false }; // Sun..Sat
        public bool LunchEnabled = true;
        public int LunchStartMin = 12 * 60;
        public int LunchEndMin = 13 * 60;

        // Eye break (20-20-20 rule)
        public int MicroIntervalMin = 20;
        public int MicroDurationSec = 20;

        // Stretch / stand-up break
        public int LongIntervalMin = 60;
        public int LongDurationMin = 5;

        // Behaviour
        public int WarningSec = 30;
        public bool StrictMode = false;
        public int MaxPostpones = 2;
        public int PostponeMin = 5;
        public bool Sounds = true;
        public int IdleResetMin = 5;
        public bool BlinkNudges = false;
        public int BlinkEveryMin = 10;

        // Guidance and smart behaviour
        public bool VoiceGuide = true;          // play media\<slug>.wav for each step
        public int VideoIntroSec = 8;           // show the demo clip this long, then dim it (0 = keep showing)
        public bool DeferDuringMeetings = true; // hold breaks while camera/mic is in use or a full-screen app is up
        public bool HandsOffCheck = true;       // break timer pauses while you keep typing / using the mouse
        public bool DailyCheckIn = true;        // ask eye-blur and energy ratings at the end of each shift

        // Interface language: "en" (English) or "tl" (Tagalog). Voice-overs stay in English.
        public string Language = "en";

        public static string Dir
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ScreenRest"); }
        }
        static string FilePath { get { return Path.Combine(Dir, "settings.ini"); } }
        public static bool Exists { get { return File.Exists(FilePath); } }

        public bool IsWorkDay(DateTime t) { return WorkDays[(int)t.DayOfWeek]; }
        static int Minute(DateTime t) { return t.Hour * 60 + t.Minute; }
        public bool InShiftHours(DateTime t)
        {
            int m = Minute(t);
            return IsWorkDay(t) && m >= ShiftStartMin && m < ShiftEndMin;
        }
        public bool InLunch(DateTime t)
        {
            int m = Minute(t);
            return LunchEnabled && m >= LunchStartMin && m < LunchEndMin;
        }
        public bool IsActiveTime(DateTime t) { return InShiftHours(t) && !InLunch(t); }

        public static string Hm(int minutes) { return string.Format("{0}:{1:00}", minutes / 60, minutes % 60); }

        public static Settings Load()
        {
            var s = new Settings();
            try
            {
                if (!File.Exists(FilePath)) return s;
                var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var line in File.ReadAllLines(FilePath))
                {
                    int i = line.IndexOf('=');
                    if (i > 0) d[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim();
                }
                s.ShiftStartMin = Int(d, "ShiftStartMin", s.ShiftStartMin);
                s.ShiftEndMin = Int(d, "ShiftEndMin", s.ShiftEndMin);
                s.LunchEnabled = Bool(d, "LunchEnabled", s.LunchEnabled);
                s.LunchStartMin = Int(d, "LunchStartMin", s.LunchStartMin);
                s.LunchEndMin = Int(d, "LunchEndMin", s.LunchEndMin);
                s.MicroIntervalMin = Int(d, "MicroIntervalMin", s.MicroIntervalMin);
                s.MicroDurationSec = Int(d, "MicroDurationSec", s.MicroDurationSec);
                s.LongIntervalMin = Int(d, "LongIntervalMin", s.LongIntervalMin);
                s.LongDurationMin = Int(d, "LongDurationMin", s.LongDurationMin);
                s.WarningSec = Int(d, "WarningSec", s.WarningSec);
                s.StrictMode = Bool(d, "StrictMode", s.StrictMode);
                s.MaxPostpones = Int(d, "MaxPostpones", s.MaxPostpones);
                s.PostponeMin = Int(d, "PostponeMin", s.PostponeMin);
                s.Sounds = Bool(d, "Sounds", s.Sounds);
                s.IdleResetMin = Int(d, "IdleResetMin", s.IdleResetMin);
                s.BlinkNudges = Bool(d, "BlinkNudges", s.BlinkNudges);
                s.BlinkEveryMin = Int(d, "BlinkEveryMin", s.BlinkEveryMin);
                s.VoiceGuide = Bool(d, "VoiceGuide", s.VoiceGuide);
                s.VideoIntroSec = Int(d, "VideoIntroSec", s.VideoIntroSec);
                s.DeferDuringMeetings = Bool(d, "DeferDuringMeetings", s.DeferDuringMeetings);
                s.HandsOffCheck = Bool(d, "HandsOffCheck", s.HandsOffCheck);
                s.DailyCheckIn = Bool(d, "DailyCheckIn", s.DailyCheckIn);
                string lang;
                if (d.TryGetValue("Language", out lang) && (lang == "en" || lang == "tl")) s.Language = lang;
                string wd;
                if (d.TryGetValue("WorkDays", out wd) && wd.Length == 7)
                    for (int i = 0; i < 7; i++) s.WorkDays[i] = wd[i] == '1';
            }
            catch { /* corrupt file: fall back to defaults */ }
            return s;
        }

        public void Save()
        {
            Directory.CreateDirectory(Dir);
            var wd = "";
            foreach (var b in WorkDays) wd += b ? "1" : "0";
            var lines = new[]
            {
                "# ScreenRest settings (times are minutes after midnight)",
                "ShiftStartMin=" + ShiftStartMin, "ShiftEndMin=" + ShiftEndMin, "WorkDays=" + wd,
                "LunchEnabled=" + LunchEnabled, "LunchStartMin=" + LunchStartMin, "LunchEndMin=" + LunchEndMin,
                "MicroIntervalMin=" + MicroIntervalMin, "MicroDurationSec=" + MicroDurationSec,
                "LongIntervalMin=" + LongIntervalMin, "LongDurationMin=" + LongDurationMin,
                "WarningSec=" + WarningSec, "StrictMode=" + StrictMode, "MaxPostpones=" + MaxPostpones,
                "PostponeMin=" + PostponeMin, "Sounds=" + Sounds, "IdleResetMin=" + IdleResetMin,
                "BlinkNudges=" + BlinkNudges, "BlinkEveryMin=" + BlinkEveryMin,
                "VoiceGuide=" + VoiceGuide, "VideoIntroSec=" + VideoIntroSec,
                "DeferDuringMeetings=" + DeferDuringMeetings, "HandsOffCheck=" + HandsOffCheck,
                "DailyCheckIn=" + DailyCheckIn, "Language=" + Language
            };
            File.WriteAllLines(FilePath, lines);
        }

        static int Int(Dictionary<string, string> d, string k, int def)
        {
            string v; int r;
            return d.TryGetValue(k, out v) && int.TryParse(v, out r) ? r : def;
        }
        static bool Bool(Dictionary<string, string> d, string k, bool def)
        {
            string v; bool r;
            return d.TryGetValue(k, out v) && bool.TryParse(v, out r) ? r : def;
        }

        // ---- Microsoft Store (MSIX) package detection ----
        [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        static extern int GetCurrentPackageFullName(ref int length, System.Text.StringBuilder name);
        static int packaged = -1;

        /// <summary>
        /// True when running from the Microsoft Store (MSIX) package. Windows then owns start-with-Windows
        /// (the manifest's StartupTask, toggled in Settings > Apps > Startup) and updates/uninstall.
        /// </summary>
        public static bool IsPackaged
        {
            get
            {
                if (packaged < 0)
                {
                    try { int len = 0; packaged = GetCurrentPackageFullName(ref len, null) == 15700 ? 0 : 1; } // 15700 = APPMODEL_ERROR_NO_PACKAGE
                    catch { packaged = 0; } // no package APIs on this Windows
                }
                return packaged == 1;
            }
        }

        // ---- Start with Windows (per-user Run key, no admin needed; not used by the Store package) ----
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        public static bool StartupEnabled
        {
            get
            {
                if (IsPackaged) return false;
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k != null && k.GetValue("ScreenRest") != null;
            }
            set
            {
                if (IsPackaged) return;
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey, true))
                {
                    if (k == null) return;
                    string exe = System.Windows.Forms.Application.ExecutablePath;
                    // Only ever register ScreenRest itself (not a host process such as a test harness).
                    if (value && !Path.GetFileName(exe).StartsWith("ScreenRest", StringComparison.OrdinalIgnoreCase)) return;
                    if (value) k.SetValue("ScreenRest", "\"" + exe + "\"");
                    else if (k.GetValue("ScreenRest") != null) k.DeleteValue("ScreenRest");
                }
            }
        }
    }
}
