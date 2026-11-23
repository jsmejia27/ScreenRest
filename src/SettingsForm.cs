using System;
using System.Drawing;
using System.Windows.Forms;

namespace ScreenRest
{
    public class SettingsForm : Form
    {
        readonly Settings s;
        readonly TableLayoutPanel grid;
        DateTimePicker dtStart, dtEnd, dtLunchS, dtLunchE;
        CheckBox chkLunch, chkStrict, chkSounds, chkStartup, chkBlink;
        CheckBox chkVoice, chkDefer, chkHandsOff, chkCheckIn;
        ComboBox cmbLang;
        NumericUpDown nIntro;
        CheckBox[] days = new CheckBox[7];
        NumericUpDown nMicroI, nMicroD, nLongI, nLongD, nWarn, nPostMax, nPostMin, nIdle, nBlink;

        public SettingsForm(Settings settings)
        {
            s = settings;
            Text = L.T("ScreenRest Settings", "ScreenRest Settings");
            Icon = IconFactory.MakeIcon(IconFactory.Brand);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Font = new Font("Segoe UI", 9.5f);
            Padding = new Padding(14);
            TopMost = true;

            grid = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Fill };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));

            Section(L.T("Language", "Wika"));
            cmbLang = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 160 };
            cmbLang.Items.AddRange(new object[] { "English", "Tagalog" });
            cmbLang.SelectedIndex = s.Language == "tl" ? 1 : 0;
            Row(L.T("Language / Wika", "Wika / Language"), cmbLang);

            Section(L.T("Work shift", "Shift sa trabaho"));
            dtStart = Time(s.ShiftStartMin); dtEnd = Time(s.ShiftEndMin);
            Row(L.T("Shift starts", "Simula ng shift"), dtStart);
            Row(L.T("Shift ends", "Tapos ng shift"), dtEnd);
            var dayPanel = new FlowLayoutPanel { AutoSize = true, Margin = new Padding(0) };
            for (int i = 0; i < 7; i++)
            {
                days[i] = new CheckBox { Text = L.Day(i), Checked = s.WorkDays[i], AutoSize = true };
                dayPanel.Controls.Add(days[i]);
            }
            Row(L.T("Work days", "Araw ng trabaho"), dayPanel);
            chkLunch = new CheckBox { Text = L.T("Pause reminders during lunch", "I-pause ang paalala tuwing tanghalian"), Checked = s.LunchEnabled, AutoSize = true };
            Row("", chkLunch);
            dtLunchS = Time(s.LunchStartMin); dtLunchE = Time(s.LunchEndMin);
            var lunch = new FlowLayoutPanel { AutoSize = true, Margin = new Padding(0) };
            lunch.Controls.Add(dtLunchS);
            lunch.Controls.Add(new Label { Text = L.T("to", "hanggang"), AutoSize = true, Margin = new Padding(4, 6, 4, 0) });
            lunch.Controls.Add(dtLunchE);
            Row(L.T("Lunch", "Tanghalian"), lunch);

            Section(L.T("Eye break (20-20-20 rule)", "Eye break (20-20-20 rule)"));
            nMicroI = Num(5, 120, s.MicroIntervalMin); Row(L.T("Every (minutes)", "Tuwing (minuto)"), nMicroI);
            nMicroD = Num(10, 120, s.MicroDurationSec); Row(L.T("Lasts (seconds)", "Tagal (segundo)"), nMicroD);

            Section(L.T("Stand-up and stretch break", "Tayo at stretch break"));
            nLongI = Num(15, 180, s.LongIntervalMin); Row(L.T("Every (minutes)", "Tuwing (minuto)"), nLongI);
            nLongD = Num(1, 20, s.LongDurationMin); Row(L.T("Lasts (minutes)", "Tagal (minuto)"), nLongD);

            Section(L.T("Guidance and smart breaks", "Gabay at matalinong breaks"));
            chkVoice = new CheckBox { Text = L.T("Voice guidance (so your eyes can leave the screen)",
                "Gabay na boses, sa English (para makaalis ang mata sa screen)"), Checked = s.VoiceGuide, AutoSize = true };
            Row("", chkVoice);
            nIntro = Num(0, 60, s.VideoIntroSec); Row(L.T("Show demo video for (s, 0 = always)", "Ipakita ang demo video nang (s, 0 = palagi)"), nIntro);
            chkDefer = new CheckBox { Text = L.T("Hold breaks during calls, presentations and full-screen apps",
                "I-hold ang break habang may tawag, presentation o full-screen app"), Checked = s.DeferDuringMeetings, AutoSize = true };
            Row("", chkDefer);
            chkHandsOff = new CheckBox { Text = L.T("Pause the break timer while I keep typing or using the mouse",
                "I-pause ang timer ng break kapag nagta-type o gumagamit pa ako ng mouse"), Checked = s.HandsOffCheck, AutoSize = true };
            Row("", chkHandsOff);
            chkCheckIn = new CheckBox { Text = L.T("End-of-shift check-in (eye blur and energy)",
                "Check-in sa dulo ng shift (labo ng mata at lakas)"), Checked = s.DailyCheckIn, AutoSize = true };
            Row("", chkCheckIn);

            Section(L.T("Behaviour", "Kilos ng app"));
            nWarn = Num(0, 120, s.WarningSec); Row(L.T("Heads-up before stretch break (s)", "Paalala bago ang stretch break (s)"), nWarn);
            nPostMin = Num(1, 30, s.PostponeMin); Row(L.T("Postpone by (minutes)", "Ipagpaliban nang (minuto)"), nPostMin);
            nPostMax = Num(0, 10, s.MaxPostpones); Row(L.T("Max postpones in a row", "Pinakamaraming sunod na pagpapaliban"), nPostMax);
            nIdle = Num(1, 60, s.IdleResetMin); Row(L.T("Away this long counts as a break (min)", "Ganito katagal na wala = break na (min)"), nIdle);
            chkStrict = new CheckBox { Text = L.T("Strict mode: breaks can't be skipped or postponed",
                "Strict mode: hindi puwedeng laktawan o ipagpaliban ang break"), Checked = s.StrictMode, AutoSize = true };
            Row("", chkStrict);
            chkSounds = new CheckBox { Text = L.T("Play sounds", "Magpatunog"), Checked = s.Sounds, AutoSize = true };
            Row("", chkSounds);
            chkBlink = new CheckBox { Text = L.T("Gentle \"blink\" notifications between breaks",
                "Mahinahong paalalang \"kumurap\" sa pagitan ng breaks"), Checked = s.BlinkNudges, AutoSize = true };
            Row("", chkBlink);
            nBlink = Num(5, 60, s.BlinkEveryMin); Row(L.T("Blink reminder every (min)", "Paalalang kumurap tuwing (min)"), nBlink);
            chkStartup = new CheckBox { Text = L.T("Start ScreenRest when I sign in to Windows",
                "Buksan ang ScreenRest pag-sign in ko sa Windows"), Checked = Settings.StartupEnabled, AutoSize = true };
            if (Settings.IsPackaged)
            {
                // Store version: Windows owns the startup entry (manifest StartupTask).
                var link = new LinkLabel { Text = L.T("Start with Windows: change it in Windows Settings > Apps > Startup",
                    "Pagbukas kasabay ng Windows: baguhin sa Windows Settings > Apps > Startup"), AutoSize = true };
                link.LinkClicked += (o, e) => { try { System.Diagnostics.Process.Start("ms-settings:startupapps"); } catch { } };
                Row("", link);
            }
            else Row("", chkStartup);

            var btns = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 14, 0, 0) };
            var ok = new Button { Text = L.T("Save", "I-save"), AutoSize = true, Padding = new Padding(10, 2, 10, 2) };
            var cancel = new Button { Text = L.T("Cancel", "Kanselahin"), AutoSize = true, Padding = new Padding(10, 2, 10, 2), DialogResult = DialogResult.Cancel };
            var defaults = new Button { Text = L.T("Reset to defaults", "Ibalik sa default"), AutoSize = true, Padding = new Padding(6, 2, 6, 2) };
            ok.Click += OnSave;
            defaults.Click += (o, e) => { ApplyFrom(new Settings()); };
            btns.Controls.AddRange(new Control[] { ok, cancel, defaults });
            grid.Controls.Add(btns);
            grid.SetColumnSpan(btns, 2);

            Controls.Add(grid);
            AcceptButton = ok;
            CancelButton = cancel;
        }

        void ApplyFrom(Settings d)
        {
            // Language is a personal choice, so "Reset to defaults" leaves it alone.
            dtStart.Value = DateTime.Today.AddMinutes(d.ShiftStartMin);
            dtEnd.Value = DateTime.Today.AddMinutes(d.ShiftEndMin);
            for (int i = 0; i < 7; i++) days[i].Checked = d.WorkDays[i];
            chkLunch.Checked = d.LunchEnabled;
            dtLunchS.Value = DateTime.Today.AddMinutes(d.LunchStartMin);
            dtLunchE.Value = DateTime.Today.AddMinutes(d.LunchEndMin);
            nMicroI.Value = d.MicroIntervalMin; nMicroD.Value = d.MicroDurationSec;
            nLongI.Value = d.LongIntervalMin; nLongD.Value = d.LongDurationMin;
            nWarn.Value = d.WarningSec; nPostMin.Value = d.PostponeMin; nPostMax.Value = d.MaxPostpones;
            nIdle.Value = d.IdleResetMin; chkStrict.Checked = d.StrictMode; chkSounds.Checked = d.Sounds;
            chkBlink.Checked = d.BlinkNudges; nBlink.Value = d.BlinkEveryMin;
            chkVoice.Checked = d.VoiceGuide; nIntro.Value = d.VideoIntroSec; chkDefer.Checked = d.DeferDuringMeetings;
            chkHandsOff.Checked = d.HandsOffCheck; chkCheckIn.Checked = d.DailyCheckIn;
        }

        static int Min(DateTimePicker p) { return p.Value.Hour * 60 + p.Value.Minute; }

        void OnSave(object sender, EventArgs e)
        {
            if (Min(dtEnd) <= Min(dtStart))
            {
                MessageBox.Show(this, L.T("The shift has to end after it starts.", "Dapat matapos ang shift pagkatapos nitong magsimula."),
                    "ScreenRest", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            if (chkLunch.Checked && Min(dtLunchE) <= Min(dtLunchS))
            {
                MessageBox.Show(this, L.T("Lunch has to end after it starts.", "Dapat matapos ang tanghalian pagkatapos nitong magsimula."),
                    "ScreenRest", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            s.Language = cmbLang.SelectedIndex == 1 ? "tl" : "en";
            s.ShiftStartMin = Min(dtStart); s.ShiftEndMin = Min(dtEnd);
            for (int i = 0; i < 7; i++) s.WorkDays[i] = days[i].Checked;
            s.LunchEnabled = chkLunch.Checked; s.LunchStartMin = Min(dtLunchS); s.LunchEndMin = Min(dtLunchE);
            s.MicroIntervalMin = (int)nMicroI.Value; s.MicroDurationSec = (int)nMicroD.Value;
            s.LongIntervalMin = (int)nLongI.Value; s.LongDurationMin = (int)nLongD.Value;
            s.WarningSec = (int)nWarn.Value; s.PostponeMin = (int)nPostMin.Value; s.MaxPostpones = (int)nPostMax.Value;
            s.IdleResetMin = (int)nIdle.Value; s.StrictMode = chkStrict.Checked; s.Sounds = chkSounds.Checked;
            s.BlinkNudges = chkBlink.Checked; s.BlinkEveryMin = (int)nBlink.Value;
            s.VoiceGuide = chkVoice.Checked; s.VideoIntroSec = (int)nIntro.Value; s.DeferDuringMeetings = chkDefer.Checked;
            s.HandsOffCheck = chkHandsOff.Checked; s.DailyCheckIn = chkCheckIn.Checked;
            try
            {
                s.Save();
                if (chkStartup.Checked != Settings.StartupEnabled) Settings.StartupEnabled = chkStartup.Checked;
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, L.T("Couldn't save settings: ", "Hindi na-save ang settings: ") + ex.Message,
                    "ScreenRest", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            DialogResult = DialogResult.OK;
            Close();
        }

        void Section(string title)
        {
            var l = new Label
            {
                Text = title,
                AutoSize = true,
                Font = new Font("Segoe UI Semibold", 10.5f),
                ForeColor = Color.FromArgb(20, 120, 105),
                Margin = new Padding(0, grid.Controls.Count == 0 ? 0 : 14, 0, 4)
            };
            grid.Controls.Add(l);
            grid.SetColumnSpan(l, 2);
        }

        void Row(string label, Control c)
        {
            grid.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left, Margin = new Padding(0, 3, 16, 3) });
            c.Margin = new Padding(0, 3, 0, 3);
            grid.Controls.Add(c);
        }

        static DateTimePicker Time(int minutes)
        {
            return new DateTimePicker
            {
                Format = DateTimePickerFormat.Custom,
                CustomFormat = "HH:mm",
                ShowUpDown = true,
                Width = 80,
                Value = DateTime.Today.AddMinutes(minutes)
            };
        }

        static NumericUpDown Num(int min, int max, int val)
        {
            return new NumericUpDown { Minimum = min, Maximum = max, Value = Math.Max(min, Math.Min(max, val)), Width = 80 };
        }
    }
}
