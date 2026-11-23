using System;
using System.Collections.Generic;
using System.Drawing;
using System.Media;
using System.Windows.Forms;

namespace ScreenRest
{
    public enum BreakKind { Eye, Stretch }
    public enum BreakResult { Completed, Skipped, Postponed }

    /// <summary>How a break behaves (built from Settings by TrayApp).</summary>
    public class BreakOptions
    {
        public bool AllowSkip = true, AllowPostpone = true, Sounds = true;
        public int PostponeMin = 5;
        public bool Voice = true;       // play media\<slug>.wav
        public int VideoIntroSec = 8;   // dim the demo clip after this long when a voice-over is guiding you (0 = never)
        public bool HandsOff = true;    // pause the countdown while keyboard/mouse are in use
    }

    /// <summary>Full-screen dimmed overlay that guides the user through a break.</summary>
    public class BreakForm : Form
    {
        public BreakResult Result = BreakResult.Completed;
        public int PausedSeconds; // time the countdown was held because you kept working

        readonly BreakKind kind;
        readonly List<Exercise> steps;
        readonly BreakOptions opt;
        readonly int totalSec;
        int elapsed, stepIdx, stepElapsed, shownSec, introUntil;
        bool finished, holding, voicePlaying, demoDimmed;

        readonly FlowLayoutPanel stack;
        readonly Label lblHeader, lblTitle, lblBody, lblTimer, lblNudge, lblNext;
        readonly BarPanel bar;
        readonly PictureBox demo;
        Image demoImage;
        System.IO.MemoryStream demoStream;
        SoundPlayer voice;
        readonly Font timerBig, timerSmall;
        readonly Timer timer;

        static readonly Color Bg = Color.FromArgb(14, 22, 28);
        static readonly Color Accent = Color.FromArgb(70, 205, 180);
        static readonly Color Soft = Color.FromArgb(200, 212, 220);
        static readonly Color Dim = Color.FromArgb(130, 145, 155);
        static readonly Color Warn = Color.FromArgb(240, 170, 80);

        public BreakForm(BreakKind kind, List<Exercise> steps, Screen screen, BreakOptions options)
        {
            this.kind = kind;
            this.steps = steps;
            opt = options;
            foreach (var s in steps) totalSec += s.Seconds;

            Text = "ScreenRest break";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = screen.Bounds;
            TopMost = true;
            ShowInTaskbar = false;
            BackColor = Bg;
            Opacity = 0.96;
            KeyPreview = true;
            DoubleBuffered = true;

            int textW = Math.Min(980, screen.Bounds.Width - 120);
            stack = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.TopDown,
                WrapContents = false,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                BackColor = Color.Transparent
            };

            lblHeader = MakeLabel(textW, 13f, FontStyle.Bold, Accent, "Segoe UI");
            lblTitle = MakeLabel(textW, 34f, FontStyle.Bold, Color.White, "Segoe UI");
            lblBody = MakeLabel(textW, 17f, FontStyle.Regular, Soft, "Segoe UI");
            timerBig = new Font("Segoe UI Light", 60f);
            timerSmall = new Font("Segoe UI Light", 40f);
            lblTimer = MakeLabel(textW, 60f, FontStyle.Regular, Color.White, "Segoe UI Light");
            lblNudge = MakeLabel(textW, 14f, FontStyle.Bold, Warn, "Segoe UI");
            bar = new BarPanel { Width = textW, Height = 8, Margin = new Padding(0, 4, 0, 18) };
            lblNext = MakeLabel(textW, 13f, FontStyle.Regular, Dim, "Segoe UI");

            lblTitle.Margin = new Padding(0, 6, 0, 14);
            lblTimer.Margin = new Padding(0, 20, 0, 0);
            lblNudge.Text = " "; // keeps its line height so the layout doesn't jump

            // Looping exercise demo (animated GIF from media\), sized to about a third of screen height.
            int demoH = Math.Max(180, Math.Min(460, screen.Bounds.Height * 9 / 25));
            int demoW = Math.Min(textW, demoH * 16 / 9);
            demo = new PictureBox
            {
                Size = new Size(demoW, demoH),
                SizeMode = PictureBoxSizeMode.Zoom,
                BackColor = Color.FromArgb(22, 32, 40),
                Anchor = AnchorStyles.None, // centred in the TopDown flow
                Margin = new Padding(0, 0, 0, 16),
                Visible = false
            };
            demo.Paint += PaintDimmedDemo;

            var buttons = new FlowLayoutPanel
            {
                FlowDirection = FlowDirection.LeftToRight,
                AutoSize = true,
                AutoSizeMode = AutoSizeMode.GrowAndShrink,
                Anchor = AnchorStyles.None,
                Margin = new Padding(0, 22, 0, 0),
                BackColor = Color.Transparent
            };
            // "Done" ends the break early and counts it as taken (you did the exercise). Strict mode keeps you in.
            if (opt.AllowSkip)
                buttons.Controls.Add(MakeButton(L.T("Done", "Tapos na"), () => Finish(BreakResult.Completed), true));
            if (opt.AllowPostpone)
                buttons.Controls.Add(MakeButton(L.T("Postpone " + opt.PostponeMin + " min", "Ipagpaliban nang " + opt.PostponeMin + " min"), () => Finish(BreakResult.Postponed)));
            if (opt.AllowSkip)
                buttons.Controls.Add(MakeButton(L.T("Skip  (Esc)", "Laktawan  (Esc)"), () => Finish(BreakResult.Skipped)));
            if (!opt.AllowSkip && !opt.AllowPostpone)
            {
                var strict = MakeLabel(textW, 11f, FontStyle.Italic, Dim, "Segoe UI");
                strict.Text = L.T("Strict mode is on. This break can't be skipped. Your body will thank you.",
                                  "Naka-on ang strict mode. Hindi puwedeng laktawan ang break na ito. Magpapasalamat ang katawan mo.");
                buttons.Controls.Add(strict);
            }

            stack.Controls.AddRange(new Control[] { lblHeader, lblTitle, demo, lblBody, lblTimer, lblNudge, bar, lblNext, buttons });
            Controls.Add(stack);

            stack.SizeChanged += (s, e) => CenterStack();
            Resize += (s, e) => CenterStack();

            KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Escape && opt.AllowSkip) Finish(BreakResult.Skipped);
                else if (e.KeyCode == Keys.V) ReplayDemo();
            };
            FormClosing += (s, e) => { if (!finished && e.CloseReason == CloseReason.UserClosing) e.Cancel = true; };

            timer = new Timer { Interval = 1000 };
            timer.Tick += OnTick;
            Shown += (s, e) =>
            {
                Activate();
                ShowStep();
                CenterStack();
                timer.Start();
            };
        }

        static Label MakeLabel(int width, float size, FontStyle style, Color color, string font)
        {
            return new Label
            {
                AutoSize = true,
                MinimumSize = new Size(width, 0),
                MaximumSize = new Size(width, 0),
                TextAlign = ContentAlignment.TopCenter,
                Font = new Font(font, size, style),
                ForeColor = color,
                BackColor = Color.Transparent,
                Margin = new Padding(0)
            };
        }

        Button MakeButton(string text, Action onClick, bool primary = false)
        {
            var b = new Button
            {
                Text = text,
                AutoSize = true,
                FlatStyle = FlatStyle.Flat,
                ForeColor = primary ? Color.White : Soft,
                BackColor = primary ? Color.FromArgb(30, 158, 138) : Color.FromArgb(30, 42, 50),
                Font = new Font("Segoe UI", 11f, primary ? FontStyle.Bold : FontStyle.Regular),
                Padding = new Padding(14, 6, 14, 6),
                Margin = new Padding(8, 0, 8, 0),
                Cursor = Cursors.Hand,
                TabStop = false
            };
            b.FlatAppearance.BorderColor = primary ? Color.FromArgb(70, 205, 180) : Color.FromArgb(60, 78, 90);
            // Run the action after the click finishes, so the window isn't closed in the middle of the button's own mouse handling.
            b.Click += (s, e) => BeginInvoke(onClick);
            return b;
        }

        void CenterStack()
        {
            stack.Location = new Point(Math.Max(0, (ClientSize.Width - stack.Width) / 2),
                                       Math.Max(0, (ClientSize.Height - stack.Height) / 2 - 20));
        }

        // ------------------------------------------------------------------ steps
        void ShowStep()
        {
            var ex = steps[stepIdx];
            if (kind == BreakKind.Eye)
            {
                lblHeader.Text = L.T("EYE BREAK  ·  LOOK AWAY FROM THE SCREEN", "EYE BREAK  ·  TUMINGIN PALAYO SA SCREEN");
                lblNext.Text = L.T("Your eyes focus up close all day. Looking far away lets the focusing muscles relax.",
                                   "Buong araw nakatutok sa malapit ang mata mo. Ang pagtingin sa malayo ay nagpapahinga sa mga kalamnan nito.");
            }
            else
                lblHeader.Text = string.Format(L.T("STRETCH BREAK  ·  STEP {0} OF {1}", "STRETCH BREAK  ·  HAKBANG {0} SA {1}"), stepIdx + 1, steps.Count);
            lblTitle.Text = ex.Title;
            lblBody.Text = ex.Steps;

            voicePlaying = PlayVoice(opt.Voice ? ex.AudioPath : null);
            if (!voicePlaying && opt.Sounds) SystemSounds.Asterisk.Play(); // chime only when there's no voice

            LoadDemo(ex.MediaPath);
            // Eye breaks are about looking away, so the clip is only a quick reminder there.
            int intro = kind == BreakKind.Eye ? Math.Min(opt.VideoIntroSec, 6) : opt.VideoIntroSec;
            introUntil = intro > 0 ? stepElapsed + intro : int.MaxValue;

            lblTimer.Font = demo.Visible ? timerSmall : timerBig;
            UpdateTimer();
        }

        bool PlayVoice(string path)
        {
            StopVoice();
            if (path == null) return false;
            try { voice = new SoundPlayer(path); voice.Play(); return true; }
            catch { voice = null; return false; }
        }

        void StopVoice()
        {
            if (voice == null) return;
            try { voice.Stop(); voice.Dispose(); } catch { }
            voice = null;
        }

        void LoadDemo(string path)
        {
            demo.Image = null;
            demoDimmed = false;
            if (demoImage != null) { demoImage.Dispose(); demoImage = null; }
            if (demoStream != null) { demoStream.Dispose(); demoStream = null; }
            if (path == null) { demo.Visible = false; return; }
            try
            {
                // Keep the stream alive for the life of the Image (GDI+ reads GIF frames lazily),
                // and read into memory so the file on disk isn't locked.
                demoStream = new System.IO.MemoryStream(System.IO.File.ReadAllBytes(path));
                demoImage = Image.FromStream(demoStream);
                demo.Image = demoImage;
                demo.Visible = true;
            }
            catch { demo.Visible = false; }
        }

        /// <summary>After the intro, hide the clip so your eyes leave the screen and the voice takes over.</summary>
        void DimDemo()
        {
            if (!demo.Visible || demoDimmed) return;
            demoDimmed = true;
            demo.Image = null;
            demo.Invalidate();
        }

        void ReplayDemo()
        {
            if (!demo.Visible || !demoDimmed || demoImage == null) return;
            demoDimmed = false;
            demo.Image = demoImage;
            introUntil = stepElapsed + Math.Max(5, opt.VideoIntroSec);
        }

        void PaintDimmedDemo(object sender, PaintEventArgs e)
        {
            if (!demoDimmed) return;
            string text = L.T("Eyes off the screen. Follow the voice.\n\nPress V to see the demo again",
                              "Alisin ang tingin sa screen. Sundan ang boses.\n\nPindutin ang V para makita ulit ang demo");
            using (var f = new Font("Segoe UI", 16f))
            using (var b = new SolidBrush(Dim))
            {
                var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                e.Graphics.DrawString(text, f, b, demo.ClientRectangle, fmt);
            }
        }

        void UpdateTimer()
        {
            int stepLeft = steps[stepIdx].Seconds - stepElapsed;
            lblTimer.Text = Clock(stepLeft);
            bar.Fraction = totalSec == 0 ? 1 : (float)elapsed / totalSec;
            if (kind == BreakKind.Stretch)
            {
                string next = stepIdx + 1 < steps.Count ? L.T("Next: ", "Susunod: ") + steps[stepIdx + 1].Title
                                                        : L.T("Last one, almost done!", "Huli na ito, malapit nang matapos!");
                lblNext.Text = next + "        ·        " + L.T(Clock(totalSec - elapsed) + " left in break", Clock(totalSec - elapsed) + " natitira sa break");
            }
        }

        static string Clock(int sec)
        {
            if (sec < 0) sec = 0;
            return string.Format("{0}:{1:00}", sec / 60, sec % 60);
        }

        void OnTick(object sender, EventArgs e)
        {
            shownSec++;

            // Hands-off check: if you're still typing or using the mouse, the break isn't happening.
            // (A short grace period at the start, since you were mid-sentence when it appeared.)
            if (opt.HandsOff && shownSec > 3 && Native.IdleMilliseconds() < 1500)
            {
                holding = true;
                PausedSeconds++;
                lblNudge.Text = kind == BreakKind.Stretch
                    ? L.T("Paused: hands off the keyboard and mouse, and stand up", "Naka-pause: bitawan ang keyboard at mouse, at tumayo")
                    : L.T("Paused: hands off the keyboard and mouse, and look away", "Naka-pause: bitawan ang keyboard at mouse, at tumingin palayo");
                return;
            }
            if (holding) { holding = false; lblNudge.Text = " "; }

            elapsed++;
            stepElapsed++;
            if (voicePlaying && stepElapsed >= introUntil) DimDemo();

            if (stepElapsed >= steps[stepIdx].Seconds)
            {
                stepIdx++;
                stepElapsed = 0;
                if (stepIdx >= steps.Count) { Finish(BreakResult.Completed); return; }
                ShowStep();
                return;
            }
            UpdateTimer();
        }

        void Finish(BreakResult r)
        {
            if (finished) return;
            finished = true;
            timer.Stop();
            StopVoice();
            Result = r;
            if (r == BreakResult.Completed && opt.Sounds) SystemSounds.Exclamation.Play();
            Close();
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                timer.Dispose();
                StopVoice();
                demo.Image = null;
                if (demoImage != null) demoImage.Dispose();
                if (demoStream != null) demoStream.Dispose();
                timerBig.Dispose();
                timerSmall.Dispose();
            }
            base.Dispose(disposing);
        }

        /// <summary>Simple flat progress bar.</summary>
        class BarPanel : Panel
        {
            float fraction;
            public float Fraction { get { return fraction; } set { fraction = Math.Max(0, Math.Min(1, value)); Invalidate(); } }
            public BarPanel() { DoubleBuffered = true; }
            protected override void OnPaint(PaintEventArgs e)
            {
                using (var bg = new SolidBrush(Color.FromArgb(40, 55, 64)))
                    e.Graphics.FillRectangle(bg, ClientRectangle);
                using (var fg = new SolidBrush(Accent))
                    e.Graphics.FillRectangle(fg, 0, 0, (int)(Width * fraction), Height);
            }
        }
    }

    /// <summary>Plain dim overlay for secondary monitors, so you can't keep working there.</summary>
    public class DimForm : Form
    {
        public DimForm(Screen screen)
        {
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = screen.Bounds;
            TopMost = true;
            ShowInTaskbar = false;
            BackColor = Color.FromArgb(14, 22, 28);
            Opacity = 0.92;
            var l = new Label
            {
                Text = L.T("Break time: look away from the screen", "Oras ng break: tumingin palayo sa screen"),
                ForeColor = Color.FromArgb(130, 145, 155),
                Font = new Font("Segoe UI", 18f),
                AutoSize = false,
                Dock = DockStyle.Fill,
                TextAlign = ContentAlignment.MiddleCenter
            };
            Controls.Add(l);
        }
        protected override bool ShowWithoutActivation { get { return true; } }
    }
}
