using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ScreenRest
{
    /// <summary>System-tray app: tracks active screen time during the shift and triggers breaks.</summary>
    public class TrayApp : ApplicationContext
    {
        readonly bool demo;
        Settings s;
        DayStats stats;
        readonly NotifyIcon tray;
        readonly Timer tick;
        readonly Icon icoActive, icoPaused, icoDue;
        ToolStripMenuItem statusItem, resumeItem;

        int sinceEye, sinceStretch, sinceBlink, saveCounter;
        bool eyeWarned, stretchWarned;
        int eyePostpones, stretchPostpones;
        DateTime pausedUntil = DateTime.MinValue;
        bool wasActive, inBreak;
        bool deferring; string deferReason; int freeTicks; // break held while in a call / presenting
        DateTime greetedDate = DateTime.MinValue, summaryDate = DateTime.MinValue;
        readonly List<Form> overlays = new List<Form>();

        // ---- intervals (seconds); demo mode shrinks them so you can try it in 2 minutes ----
        int EyeEvery { get { return demo ? 30 : s.MicroIntervalMin * 60; } }
        int EyeLength { get { return demo ? 8 : s.MicroDurationSec; } }
        int StretchEvery { get { return demo ? 90 : s.LongIntervalMin * 60; } }
        int StretchLength { get { return demo ? 40 : s.LongDurationMin * 60; } }
        int StretchWarn { get { return demo ? 10 : s.WarningSec; } }
        int EyeWarn { get { return Math.Min(10, EyeEvery / 3); } }

        public TrayApp(bool demo)
        {
            this.demo = demo;
            DayStats.DemoMode = demo; // demo runs keep their own stats file
            s = Settings.Load();
            L.Set(s.Language);
            stats = DayStats.LoadToday();

            icoActive = IconFactory.MakeIcon(IconFactory.Brand);
            icoPaused = IconFactory.MakeIcon(IconFactory.Paused);
            icoDue = IconFactory.MakeIcon(IconFactory.Due);

            tray = new NotifyIcon { Icon = icoActive, Visible = true, Text = "ScreenRest" };
            tray.DoubleClick += (o, e) => ShowDashboard(1);
            BuildMenu();

            tick = new Timer { Interval = 1000 };
            tick.Tick += OnTick;
            tick.Start();

            string mode = demo ? L.T("DEMO MODE: eye break every 30 s, stretch every 90 s.",
                                     "DEMO MODE: eye break tuwing 30 s, stretch tuwing 90 s.") :
                string.Format(L.T("Active {0}–{1}. Eye break every {2} min, stretch break every {3} min.",
                                  "Aktibo {0}–{1}. Eye break tuwing {2} min, stretch break tuwing {3} min."),
                    Settings.Hm(s.ShiftStartMin), Settings.Hm(s.ShiftEndMin), s.MicroIntervalMin, s.LongIntervalMin);
            if (!demo && !Settings.Exists) ShowWelcome();
            else Balloon(L.T("ScreenRest is running", "Tumatakbo na ang ScreenRest"),
                mode + L.T(" Right-click the eye icon near the clock for options.",
                           " I-right-click ang icon na mata malapit sa orasan para sa mga opsyon."));
            Refresh();
        }

        /// <summary>(Re)builds the tray menu in the current language.</summary>
        void BuildMenu()
        {
            var menu = new ContextMenuStrip();
            statusItem = new ToolStripMenuItem("ScreenRest") { Enabled = false };
            menu.Items.Add(statusItem);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(L.T("Take an eye break now", "Mag-eye break ngayon"), null, (o, e) => StartBreak(BreakKind.Eye));
            menu.Items.Add(L.T("Take a stretch break now", "Mag-stretch break ngayon"), null, (o, e) => StartBreak(BreakKind.Stretch));
            var pause = new ToolStripMenuItem(L.T("Pause reminders", "I-pause ang mga paalala"));
            pause.DropDownItems.Add(L.T("30 minutes (meeting)", "30 minuto (meeting)"), null, (o, e) => PauseFor(TimeSpan.FromMinutes(30)));
            pause.DropDownItems.Add(L.T("1 hour", "1 oras"), null, (o, e) => PauseFor(TimeSpan.FromHours(1)));
            pause.DropDownItems.Add(L.T("2 hours", "2 oras"), null, (o, e) => PauseFor(TimeSpan.FromHours(2)));
            pause.DropDownItems.Add(L.T("Rest of today", "Buong araw ngayon"), null, (o, e) => { pausedUntil = DateTime.Today.AddDays(1); Refresh(); });
            menu.Items.Add(pause);
            resumeItem = new ToolStripMenuItem(L.T("Resume reminders", "Ituloy ang mga paalala"), null, (o, e) => { pausedUntil = DateTime.MinValue; Refresh(); });
            menu.Items.Add(resumeItem);
            menu.Items.Add(new ToolStripSeparator());
            var dash = new ToolStripMenuItem(L.T("Dashboard...", "Dashboard..."), null, (o, e) => ShowDashboard(1));
            dash.Font = new Font(dash.Font, FontStyle.Bold); // also what double-clicking the tray icon opens
            menu.Items.Add(dash);
            menu.Items.Add(L.T("Daily check-in...", "Pang-araw-araw na check-in..."), null, (o, e) => ShowCheckIn(false));
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(L.T("Settings...", "Settings..."), null, (o, e) => ShowSettings());
            menu.Items.Add(L.T("About ScreenRest", "Tungkol sa ScreenRest"), null, (o, e) => new AboutForm().Show());
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(L.T("Exit ScreenRest", "Isara ang ScreenRest"), null, (o, e) => ExitApp());
            menu.Opening += (o, e) => { statusItem.Text = StatusText(); resumeItem.Visible = DateTime.Now < pausedUntil; };

            var old = tray.ContextMenuStrip;
            tray.ContextMenuStrip = menu;
            if (old != null) old.Dispose();
        }

        /// <summary>First run only: introduce the tray icon and schedule, then save defaults so it isn't shown again.</summary>
        void ShowWelcome()
        {
            var w = new WelcomeForm(s);
            w.FormClosed += (o, e) =>
            {
                try { s.Save(); } catch { }
                L.Set(s.Language);
                BuildMenu();
                if (w.OpenSettings) ShowSettings();
                else if (w.TryBreak) StartBreak(BreakKind.Eye);
                else Balloon(L.T("ScreenRest is running", "Tumatakbo na ang ScreenRest"),
                    L.T("Right-click the eye icon near the clock for breaks, stats and settings.",
                        "I-right-click ang icon na mata malapit sa orasan para sa breaks, stats at settings."));
                Refresh();
            };
            w.Show();
        }

        // ------------------------------------------------------------------ main loop
        void OnTick(object sender, EventArgs e)
        {
            var now = DateTime.Now;
            if (stats.Date != DateTime.Today) { stats.Save(); stats = DayStats.LoadToday(); }

            bool active = demo || s.IsActiveTime(now);
            if (active && !wasActive) OnShiftEnter(now);
            if (!active && wasActive && !demo && s.IsWorkDay(now) && now.Hour * 60 + now.Minute >= s.ShiftEndMin) OnShiftEnd();
            wasActive = active;

            if (inBreak || !active || now < pausedUntil) { Refresh(); return; }

            // Natural break: if you've been away from the keyboard/mouse long enough, that counts.
            int idle = Native.IdleSeconds();
            int idleReset = demo ? 20 : s.IdleResetMin * 60;
            if (idle >= idleReset)
            {
                ResetEye();
                if (idle >= Math.Max(idleReset, StretchLength)) ResetStretch();
                Refresh();
                return;
            }

            sinceEye++; sinceStretch++; sinceBlink++;
            stats.ActiveSec++;
            if (++saveCounter >= 60) { saveCounter = 0; stats.Save(); }

            int toStretch = StretchEvery - sinceStretch;
            int toEye = EyeEvery - sinceEye;

            BreakKind? due = null;
            if (toStretch <= 0) due = BreakKind.Stretch;
            else if (toEye <= 0)
            {
                // A stretch break is coming soon anyway, so skip this eye break.
                if (toStretch <= 120 && !demo) ResetEye();
                else due = BreakKind.Eye;
            }
            if (due.HasValue)
            {
                // Never pop up in the middle of a video call, presentation or full-screen video.
                string why;
                if (s.DeferDuringMeetings && Native.IsBusy(out why))
                {
                    if (!deferring)
                    {
                        deferring = true;
                        deferReason = why;
                        bool st = due.Value == BreakKind.Stretch;
                        Balloon(L.T("Break on hold", "Naka-hold ang break"),
                            L.T("It looks like " + why + ". Your " + (st ? "stretch" : "eye") + " break will start once you're free.",
                                "Mukhang " + why + ". Magsisimula ang iyong " + (st ? "stretch" : "eye") + " break kapag libre ka na."));
                    }
                    freeTicks = 0;
                    Refresh();
                    return;
                }
                if (deferring && ++freeTicks < 10) { Refresh(); return; } // 10 s grace after the call ends
                deferring = false; freeTicks = 0;
                StartBreak(due.Value);
                return;
            }

            if (!stretchWarned && StretchWarn > 0 && toStretch <= StretchWarn)
            {
                stretchWarned = true;
                Balloon(L.T("Stretch break in " + toStretch + " seconds", "Stretch break sa loob ng " + toStretch + " segundo"),
                    L.T("Finish your thought. Time to stand up and move soon.",
                        "Tapusin na ang ginagawa. Malapit na ang oras para tumayo at gumalaw."));
            }
            else if (!eyeWarned && toEye <= EyeWarn && toStretch > toEye + 5)
            {
                eyeWarned = true;
                Balloon(L.T("Eye break in " + toEye + " seconds", "Eye break sa loob ng " + toEye + " segundo"),
                    L.T("Get ready to look away from the screen.", "Humanda nang tumingin palayo sa screen."));
            }
            else if (s.BlinkNudges && !demo && sinceBlink >= s.BlinkEveryMin * 60 && toEye > 60 && toStretch > 60)
            {
                sinceBlink = 0;
                Balloon(L.T("Blink", "Kumurap"),
                    L.T("Blink slowly a few times, and relax your shoulders.",
                        "Kumurap nang dahan-dahan nang ilang beses, at i-relax ang mga balikat."));
            }
            Refresh();
        }

        void OnShiftEnter(DateTime now)
        {
            ResetEye(); ResetStretch();
            if (demo) return;
            if (greetedDate != now.Date)
            {
                greetedDate = now.Date;
                Balloon(L.T("Good morning! Your shift has started", "Magandang umaga! Nagsimula na ang shift mo"),
                    L.T("ScreenRest will remind you to rest your eyes and stand up until " + Settings.Hm(s.ShiftEndMin) + ".",
                        "Paaalalahanan ka ng ScreenRest na ipahinga ang mata at tumayo hanggang " + Settings.Hm(s.ShiftEndMin) + "."));
            }
            else Balloon(L.T("Welcome back", "Maligayang pagbabalik"), L.T("Reminders are on again.", "Bukas na ulit ang mga paalala."));
        }

        void OnShiftEnd()
        {
            if (summaryDate == DateTime.Today) return;
            summaryDate = DateTime.Today;
            stats.Save();
            Balloon(L.T("Shift done. Time to log off!", "Tapos na ang shift. Oras nang mag-log off!"),
                string.Format(L.T("Eye breaks {0}/{1} · Stretch {2}/{3} · Score {4}%. Now go outside and look far away.",
                                  "Eye breaks {0}/{1} · Stretch {2}/{3} · Score {4}%. Lumabas ka at tumanaw sa malayo."),
                    stats.EyeTaken, stats.EyeTaken + stats.EyeSkipped, stats.StretchTaken,
                    stats.StretchTaken + stats.StretchSkipped, stats.Score));
            if (s.DailyCheckIn) ShowCheckIn(IsLastWorkDayOfWeek(DateTime.Today));
            else if (IsLastWorkDayOfWeek(DateTime.Today)) ShowWeekly();
        }

        /// <summary>Last ticked work day in a Monday-to-Sunday week (Friday by default).</summary>
        bool IsLastWorkDayOfWeek(DateTime d)
        {
            int[] order = { 1, 2, 3, 4, 5, 6, 0 };
            int last = -1;
            foreach (int i in order) if (s.WorkDays[i]) last = i;
            return last == (int)d.DayOfWeek;
        }

        CheckInForm checkIn;
        void ShowCheckIn(bool thenWeekly)
        {
            if (checkIn != null && !checkIn.IsDisposed) { checkIn.Activate(); return; }
            checkIn = new CheckInForm(stats);
            checkIn.FormClosed += (o, e) =>
            {
                checkIn = null;
                if (dashboard != null && !dashboard.IsDisposed) dashboard.Reload();
                if (thenWeekly) ShowWeekly();
            };
            checkIn.Show();
        }

        /// <summary>End of the week: the Dashboard opens on the last 7 days.</summary>
        void ShowWeekly() { ShowDashboard(7); }

        DashboardForm dashboard;
        void ShowDashboard(int range)
        {
            stats.Save();
            if (dashboard != null && !dashboard.IsDisposed) { dashboard.ShowRange(range); return; }
            dashboard = new DashboardForm(range, () => stats, () => s.DailyCheckIn, () => ShowCheckIn(false));
            dashboard.FormClosed += (o, e) => dashboard = null;
            dashboard.Show();
        }

        void ResetEye() { sinceEye = 0; eyeWarned = false; sinceBlink = 0; }
        void ResetStretch() { sinceStretch = 0; stretchWarned = false; }

        // ------------------------------------------------------------------ breaks
        void StartBreak(BreakKind kind)
        {
            if (inBreak) return;
            inBreak = true;
            tray.Icon = icoDue;

            var steps = kind == BreakKind.Eye ? Exercises.EyeBreak(EyeLength) : Exercises.StretchRoutine(StretchLength);
            int postpones = kind == BreakKind.Eye ? eyePostpones : stretchPostpones;
            var opt = new BreakOptions
            {
                AllowSkip = !s.StrictMode,
                AllowPostpone = !s.StrictMode && postpones < s.MaxPostpones,
                PostponeMin = demo ? 1 : s.PostponeMin,
                Sounds = s.Sounds,
                Voice = s.VoiceGuide,
                VideoIntroSec = s.VideoIntroSec,
                HandsOff = s.HandsOffCheck
            };

            var target = Screen.FromPoint(Cursor.Position);
            var main = new BreakForm(kind, steps, target, opt);
            foreach (var scr in Screen.AllScreens)
            {
                if (scr.DeviceName == target.DeviceName) continue;
                var d = new DimForm(scr);
                overlays.Add(d);
                d.Show();
            }
            main.FormClosed += (o, e) =>
            {
                if (inBreak)
                    BreakLog.Append(new BreakEntry { Time = DateTime.Now, Kind = kind, Result = main.Result,
                        PlannedSec = main.PlannedSeconds, TakenSec = main.ElapsedSeconds, PausedSec = main.PausedSeconds });
                EndBreak(kind, main.Result);
            };
            overlays.Add(main);
            main.Show();
        }

        void EndBreak(BreakKind kind, BreakResult r)
        {
            // Runs from the break window's FormClosed event. Calling Close() on that window again from here
            // raised FormClosed again and recursed until the process died (stack overflow, tray icon gone).
            // So: run once, empty the list first, and close only the dimmed windows on the other screens.
            if (!inBreak) return;
            inBreak = false;
            var others = overlays.ToArray();
            overlays.Clear();
            foreach (var f in others) { if (!(f is BreakForm) && !f.IsDisposed) f.Close(); }

            int postponeSec = (demo ? 1 : s.PostponeMin) * 60;
            if (kind == BreakKind.Eye)
            {
                if (r == BreakResult.Postponed) { sinceEye = Math.Max(0, EyeEvery - postponeSec); eyeWarned = false; eyePostpones++; stats.Postponed++; }
                else { if (r == BreakResult.Completed) stats.EyeTaken++; else stats.EyeSkipped++; ResetEye(); eyePostpones = 0; }
            }
            else
            {
                if (r == BreakResult.Postponed) { sinceStretch = Math.Max(0, StretchEvery - postponeSec); stretchWarned = false; stretchPostpones++; stats.Postponed++; }
                else
                {
                    if (r == BreakResult.Completed) stats.StretchTaken++; else stats.StretchSkipped++;
                    ResetStretch(); ResetEye(); stretchPostpones = 0;
                }
            }
            stats.Save();
            if (r == BreakResult.Completed)
                Balloon(kind == BreakKind.Eye ? L.T("Eyes rested", "Napahinga ang mata") : L.T("Nice work, you moved!", "Galing, gumalaw ka!"),
                    L.T("Break score today: " + stats.Score + "%. Keep it up.",
                        "Break score ngayong araw: " + stats.Score + "%. Ituloy mo lang."));
            Refresh();
        }

        // ------------------------------------------------------------------ UI helpers
        void PauseFor(TimeSpan t) { pausedUntil = DateTime.Now + t; Refresh(); }

        string StatusText()
        {
            var now = DateTime.Now;
            if (inBreak) return L.T("On a break", "Naka-break");
            if (deferring) return L.T("Break on hold: ", "Naka-hold ang break: ") + deferReason;
            if (now < pausedUntil)
                return pausedUntil.Date > now.Date ? L.T("Paused for the rest of today", "Naka-pause buong araw ngayon")
                                                   : L.T("Paused until ", "Naka-pause hanggang ") + pausedUntil.ToString("HH:mm");
            if (!demo)
            {
                if (!s.IsWorkDay(now)) return L.T("Day off, no reminders", "Day off, walang paalala");
                if (s.InShiftHours(now) && s.InLunch(now)) return L.T("Lunch break, enjoy it", "Lunch break, mag-enjoy ka");
                if (!s.InShiftHours(now)) return string.Format(L.T("Off shift (active {0}–{1})", "Wala sa shift (aktibo {0}–{1})"),
                    Settings.Hm(s.ShiftStartMin), Settings.Hm(s.ShiftEndMin));
            }
            return string.Format(L.T("Eye break in {0} · stretch in {1}", "Eye break sa {0} · stretch sa {1}"),
                Left(EyeEvery - sinceEye), Left(StretchEvery - sinceStretch));
        }

        static string Left(int sec)
        {
            if (sec < 0) sec = 0;
            return sec >= 60 ? (sec / 60) + "m" : sec + "s";
        }

        void Refresh()
        {
            string t = "ScreenRest: " + StatusText();
            tray.Text = t.Length > 63 ? t.Substring(0, 63) : t;
            var now = DateTime.Now;
            bool idleState = now < pausedUntil || (!demo && !s.IsActiveTime(now));
            var icon = inBreak ? icoDue : idleState ? icoPaused : icoActive;
            // Optional countdown on the icon: minutes to the next break (rounded up, so "1" is the last minute).
            if (s.TrayCountdown && !inBreak && !idleState && !deferring)
            {
                int next = Math.Max(0, Math.Min(EyeEvery - sinceEye, StretchEvery - sinceStretch));
                int mins = (next + 59) / 60;
                if (mins >= 1 && mins <= 99)
                {
                    if (mins != countMinutes)
                    {
                        var old = icoCount;
                        icoCount = IconFactory.MakeNumberIcon(mins.ToString(), IconFactory.Brand);
                        countMinutes = mins;
                        tray.Icon = icoCount;
                        if (old != null) old.Dispose();
                    }
                    icon = icoCount;
                }
            }
            if (tray.Icon != icon) tray.Icon = icon;
        }

        Icon icoCount;
        int countMinutes = -1;

        void Balloon(string title, string text)
        {
            tray.ShowBalloonTip(6000, title, text, ToolTipIcon.Info);
        }

        SettingsForm settingsForm;
        void ShowSettings()
        {
            if (settingsForm != null && !settingsForm.IsDisposed) { settingsForm.Activate(); return; }
            settingsForm = new SettingsForm(s);
            settingsForm.FormClosed += (o, e) =>
            {
                if (settingsForm.DialogResult == DialogResult.OK)
                {
                    string oldLanguage = s.Language;
                    s = Settings.Load();
                    L.Set(s.Language);
                    BuildMenu();
                    // The Dashboard's labels are built once; reopen it in the new language.
                    if (dashboard != null && !dashboard.IsDisposed)
                    {
                        if (s.Language != oldLanguage) { dashboard.Close(); ShowDashboard(1); }
                        else dashboard.Reload();
                    }
                    Balloon(L.T("Settings saved", "Na-save ang settings"), StatusText());
                }
                settingsForm = null;
                Refresh();
            };
            settingsForm.Show();
        }

        void ExitApp()
        {
            tick.Stop();
            stats.Save();
            tray.Visible = false;
            tray.Dispose();
            ExitThread();
        }
    }
}
