using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Reflection;
using System.Windows.Forms;

namespace ScreenRest
{
    /// <summary>Shared look for the branded dialogs (welcome, about): dark panel matching the break screen.</summary>
    public abstract class BrandForm : Form
    {
        protected static readonly Color Bg = Color.FromArgb(14, 22, 28);
        protected static readonly Color Panel2 = Color.FromArgb(22, 32, 40);
        protected static readonly Color Accent = Color.FromArgb(70, 205, 180);
        protected static readonly Color Soft = Color.FromArgb(200, 212, 220);
        protected static readonly Color Dim = Color.FromArgb(130, 145, 155);

        protected readonly FlowLayoutPanel Body;

        protected BrandForm(string title)
        {
            Text = title;
            Icon = IconFactory.MakeIcon(IconFactory.Brand);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Bg;
            ForeColor = Soft;
            Font = new Font("Segoe UI", 10.5f);
            AutoSize = true; AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = new Padding(28, 24, 28, 22);
            TopMost = true;

            Body = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true, BackColor = Bg, Location = new Point(28, 24) };
            Controls.Add(Body);
        }

        public static string Version
        {
            get
            {
                var a = (AssemblyInformationalVersionAttribute)Attribute.GetCustomAttribute(
                    typeof(BrandForm).Assembly, typeof(AssemblyInformationalVersionAttribute));
                return a != null ? a.InformationalVersion : "1.0";
            }
        }

        public static string Copyright
        {
            get
            {
                var a = (AssemblyCopyrightAttribute)Attribute.GetCustomAttribute(
                    typeof(BrandForm).Assembly, typeof(AssemblyCopyrightAttribute));
                return a != null ? a.Copyright : "";
            }
        }

        protected Control Header(string title, string subtitle)
        {
            var row = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, AutoSize = true, WrapContents = false, Margin = new Padding(0, 0, 0, 16) };
            var logo = new PictureBox { Size = new Size(56, 56), Image = IconFactory.Draw(56, IconFactory.Brand), Margin = new Padding(0, 2, 14, 0) };
            var text = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false };
            text.Controls.Add(new Label { Text = title, AutoSize = true, ForeColor = Color.White, Font = new Font("Segoe UI Semibold", 18f), Margin = new Padding(0) });
            text.Controls.Add(new Label { Text = subtitle, AutoSize = true, ForeColor = Accent, Font = new Font("Segoe UI", 10.5f), Margin = new Padding(2, 0, 0, 0) });
            row.Controls.Add(logo);
            row.Controls.Add(text);
            return row;
        }

        protected Label Para(string text, Color color, int bottom)
        {
            return new Label { Text = text, AutoSize = true, MaximumSize = new Size(500, 0), ForeColor = color, Margin = new Padding(0, 0, 0, bottom) };
        }

        protected Button MakeButton(string text, bool primary)
        {
            var b = new Button
            {
                Text = text, AutoSize = true, FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand,
                Padding = new Padding(14, 5, 14, 5), Margin = new Padding(10, 0, 0, 0),
                BackColor = primary ? Color.FromArgb(30, 158, 138) : Panel2,
                ForeColor = primary ? Color.White : Soft,
                Font = new Font("Segoe UI Semibold", 10.5f)
            };
            b.FlatAppearance.BorderColor = primary ? Color.FromArgb(30, 158, 138) : Color.FromArgb(60, 78, 90);
            return b;
        }

        protected FlowLayoutPanel ButtonRow()
        {
            return new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Anchor = AnchorStyles.Right, Margin = new Padding(0, 18, 0, 0), BackColor = Bg };
        }
    }

    /// <summary>First run: language choice, the tray icon and the schedule, start-with-Windows and a sample break.</summary>
    public class WelcomeForm : BrandForm
    {
        public bool TryBreak, OpenSettings;
        readonly Settings s;
        bool startupChecked = true;

        public WelcomeForm(Settings settings) : base("ScreenRest")
        {
            s = settings;
            Build();
            FormClosed += (o, e) => { try { Settings.StartupEnabled = startupChecked; } catch { } };
        }

        /// <summary>Lays out the whole window in the current language; called again when the language changes.</summary>
        void Build()
        {
            SuspendLayout();
            Body.Controls.Clear();
            Text = L.T("Welcome to ScreenRest", "Maligayang pagdating sa ScreenRest");

            // Language picker first, so a Tagalog speaker can switch before reading anything else.
            var lang = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, AutoSize = true, WrapContents = false, Margin = new Padding(0, 0, 0, 12), BackColor = Bg };
            lang.Controls.Add(new Label { Text = "Language / Wika:", AutoSize = true, ForeColor = Dim, Margin = new Padding(0, 7, 8, 0) });
            lang.Controls.Add(LangButton("English", "en"));
            lang.Controls.Add(LangButton("Tagalog", "tl"));
            Body.Controls.Add(lang);

            Body.Controls.Add(Header(L.T("Welcome to ScreenRest", "Maligayang pagdating!"),
                L.T("Rest your eyes. Move your body. Every workday.", "Ipahinga ang mata. Igalaw ang katawan. Araw-araw sa trabaho.")));
            Body.Controls.Add(Para(L.T(
                "ScreenRest runs quietly in the system tray: look for the green eye icon near the clock " +
                "(click the ^ arrow if you don't see it). Right-click it any time for breaks, stats and settings.",
                "Tahimik na tumatakbo ang ScreenRest sa system tray: hanapin ang berdeng icon na mata malapit sa orasan " +
                "(i-click ang ^ kung hindi mo makita). I-right-click ito anumang oras para sa breaks, stats at settings."), Soft, 14));

            var plan = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, BackColor = Panel2, Padding = new Padding(14, 10, 14, 10), Margin = new Padding(0, 0, 0, 14) };
            plan.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            plan.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            AddPlan(plan, L.T("Your shift", "Iyong shift"),
                string.Format(L.T("{0} to {1}, {2}", "{0} hanggang {1}, {2}"), Settings.Hm(s.ShiftStartMin), Settings.Hm(s.ShiftEndMin), Days(s)));
            AddPlan(plan, L.T("Every " + s.MicroIntervalMin + " min", "Tuwing " + s.MicroIntervalMin + " min"),
                L.T(s.MicroDurationSec + "-second eye break: look far away (the 20-20-20 rule)",
                    s.MicroDurationSec + " segundong eye break: tumingin sa malayo (ang 20-20-20 rule)"));
            AddPlan(plan, L.T("Every " + s.LongIntervalMin + " min", "Tuwing " + s.LongIntervalMin + " min"),
                L.T(s.LongDurationMin + "-minute stretch break on your feet, with video and voice",
                    s.LongDurationMin + " minutong stretch break nang nakatayo, may video at boses"));
            if (s.LunchEnabled) AddPlan(plan, L.T("Lunch", "Tanghalian"),
                Settings.Hm(s.LunchStartMin) + L.T(" to ", " hanggang ") + Settings.Hm(s.LunchEndMin) + L.T(": no reminders", ": walang paalala"));
            Body.Controls.Add(plan);

            Body.Controls.Add(Para(L.T("Breaks wait while you're on a call or presenting. Everything stays on this PC.",
                "Naghihintay ang break habang nasa tawag o nagpe-present ka. Lahat ay nananatili sa PC na ito."), Dim, 10));
            if (L.Tl) Body.Controls.Add(Para("Paalala: ang gabay na boses ay nasa English pa.", Dim, 10));

            var startup = new CheckBox { Text = L.T("Start ScreenRest when I sign in to Windows", "Buksan ang ScreenRest pag-sign in ko sa Windows"),
                Checked = startupChecked, AutoSize = true, ForeColor = Soft, Margin = new Padding(0, 4, 0, 0) };
            startup.CheckedChanged += (o, e) => startupChecked = startup.Checked;
            Body.Controls.Add(startup);

            var row = ButtonRow();
            var go = MakeButton(L.T("Get started", "Simulan na"), true);
            var tryIt = MakeButton(L.T("Try a 20-second break", "Subukan ang 20-segundong break"), false);
            var change = MakeButton(L.T("Change my schedule...", "Baguhin ang iskedyul..."), false);
            go.Click += (o, e) => Close();
            tryIt.Click += (o, e) => { TryBreak = true; Close(); };
            change.Click += (o, e) => { OpenSettings = true; Close(); };
            row.Controls.AddRange(new Control[] { go, tryIt, change });
            Body.Controls.Add(row);
            AcceptButton = go;
            ResumeLayout(true);
        }

        Button LangButton(string text, string code)
        {
            bool on = s.Language == code;
            var b = MakeButton(text, on);
            b.Margin = new Padding(0, 0, 8, 0);
            b.Padding = new Padding(10, 2, 10, 2);
            b.Font = new Font("Segoe UI", 10f);
            b.Click += (o, e) =>
            {
                if (s.Language == code) return;
                s.Language = code;
                L.Set(code);
                Build();
            };
            return b;
        }

        void AddPlan(TableLayoutPanel t, string when, string what)
        {
            t.Controls.Add(new Label { Text = when, AutoSize = true, ForeColor = Accent, Font = new Font("Segoe UI Semibold", 10.5f), Margin = new Padding(0, 3, 18, 3) });
            t.Controls.Add(new Label { Text = what, AutoSize = true, MaximumSize = new Size(360, 0), ForeColor = Soft, Margin = new Padding(0, 3, 0, 3) });
        }

        static string Days(Settings s)
        {
            string mf = "0111110", cur = "";
            foreach (var b in s.WorkDays) cur += b ? "1" : "0";
            if (cur == mf) return L.T("Monday to Friday", "Lunes hanggang Biyernes");
            var parts = new System.Collections.Generic.List<string>();
            for (int i = 0; i < 7; i++) if (s.WorkDays[i]) parts.Add(L.Day(i));
            return string.Join(", ", parts.ToArray());
        }
    }

    /// <summary>About box: version, copyright, privacy note, data folder.</summary>
    public class AboutForm : BrandForm
    {
        public AboutForm() : base(L.T("About ScreenRest", "Tungkol sa ScreenRest"))
        {
            Body.Controls.Add(Header("ScreenRest", L.T("Version ", "Bersyon ") + Version));
            Body.Controls.Add(Para(L.T(
                "A break coach for people who spend the day at a screen. Eye breaks follow the " +
                "20-20-20 rule; stretch breaks get you standing, moving and drinking water, guided by video and voice.",
                "Isang break coach para sa mga buong araw nakaharap sa screen. Ang eye breaks ay sumusunod sa " +
                "20-20-20 rule; ang stretch breaks ay nagpapatayo, nagpapagalaw at nagpapainom sa iyo ng tubig, may gabay na video at boses."), Soft, 12));
            Body.Controls.Add(Para(L.T(
                "Private by design: no account, no ads, no internet connection. Your settings and stats are plain files in ",
                "Pribado: walang account, walang ads, walang internet. Ang iyong settings at stats ay simpleng files sa ") +
                DayStats.DataFolder, Dim, 12));
            Body.Controls.Add(Para(L.T(
                "ScreenRest is a wellness reminder, not medical advice. If your vision stays blurry, see an optometrist.",
                "Ang ScreenRest ay paalala para sa kalusugan, hindi payong medikal. Kung patuloy na malabo ang paningin mo, magpatingin sa optometrist."), Dim, 12));
            Body.Controls.Add(Para(Copyright, Soft, 4));
            Body.Controls.Add(Para(L.T("Free to use. Please don't resell or redistribute modified copies.",
                "Libreng gamitin. Huwag ibenta o ipamahagi ang binagong kopya."), Dim, 4));

            var row = ButtonRow();
            var ok = MakeButton(L.T("Close", "Isara"), true);
            var data = MakeButton(L.T("Open data folder", "Buksan ang data folder"), false);
            ok.Click += (o, e) => Close();
            data.Click += (o, e) => { try { Process.Start("explorer.exe", DayStats.DataFolder); } catch { } };
            row.Controls.AddRange(new Control[] { ok, data });
            Body.Controls.Add(row);
            AcceptButton = ok;
            CancelButton = ok;
        }
    }
}
