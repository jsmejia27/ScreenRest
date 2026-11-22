using System;
using System.Globalization;

namespace ScreenRest
{
    /// <summary>
    /// Tiny two-language switch (English / Tagalog). Every user-facing string is written as
    /// L.T("English", "Tagalog") so both versions sit side by side in the code.
    /// </summary>
    public static class L
    {
        /// <summary>True when the interface is in Tagalog (Settings.Language == "tl").</summary>
        public static bool Tl;

        public static void Set(string code) { Tl = string.Equals(code, "tl", StringComparison.OrdinalIgnoreCase); }
        public static string Code { get { return Tl ? "tl" : "en"; } }

        public static string T(string en, string tl) { return Tl ? tl : en; }

        static CultureInfo fil;
        static CultureInfo Culture
        {
            get
            {
                if (!Tl) return CultureInfo.CurrentCulture;
                if (fil == null)
                {
                    try { fil = CultureInfo.GetCultureInfo("fil-PH"); }
                    catch { fil = CultureInfo.CurrentCulture; }
                }
                return fil;
            }
        }

        /// <summary>Date in the interface language, e.g. "Mon 3 Nov" / "Lun 3 Nob".</summary>
        public static string Date(DateTime d, string format) { return d.ToString(format, Culture); }

        static readonly string[] DaysEn = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
        static readonly string[] DaysTl = { "Lin", "Lun", "Mar", "Miy", "Huw", "Biy", "Sab" };
        public static string Day(int i) { return Tl ? DaysTl[i] : DaysEn[i]; }
    }
}
