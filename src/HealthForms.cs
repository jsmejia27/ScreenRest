using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace ScreenRest
{
    /// <summary>End-of-shift check-in: two 1-5 ratings, saved into today's stats row.</summary>
    public class CheckInForm : Form
    {
        readonly DayStats day;
        readonly RadioButton[] blur = new RadioButton[5], energy = new RadioButton[5];

        public CheckInForm(DayStats day)
        {
            this.day = day;
            Text = L.T("ScreenRest: daily check-in", "ScreenRest: pang-araw-araw na check-in");
            Icon = IconFactory.MakeIcon(IconFactory.Brand);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoSize = true; AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Font = new Font("Segoe UI", 10f);
            Padding = new Padding(16);
            TopMost = true;

            var grid = new TableLayoutPanel { ColumnCount = 1, AutoSize = true, Dock = DockStyle.Fill };
            grid.Controls.Add(new Label
            {
                Text = L.T("How were you today? It takes 5 seconds, and over time it shows whether breaks help.",
                           "Kumusta ka ngayong araw? 5 segundo lang ito, at sa paglipas ng panahon makikita kung nakakatulong ang breaks."),
                AutoSize = true, MaximumSize = new Size(520, 0), Margin = new Padding(0, 0, 0, 10)
            });
            grid.Controls.Add(Row(L.T("Right eye blur", "Labo ng kanang mata"), L.T("1 = clear", "1 = malinaw"), L.T("5 = very blurry", "5 = napakalabo"), blur, day.EyeBlur));
            grid.Controls.Add(Row(L.T("Energy", "Lakas"), L.T("1 = exhausted", "1 = pagod na pagod"), L.T("5 = great", "5 = napakasigla"), energy, day.Energy));

            var btns = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Dock = DockStyle.Fill, Margin = new Padding(0, 12, 0, 0) };
            var save = new Button { Text = L.T("Save", "I-save"), AutoSize = true, Padding = new Padding(10, 2, 10, 2) };
            var later = new Button { Text = L.T("Not today", "Hindi ngayon"), AutoSize = true, Padding = new Padding(10, 2, 10, 2), DialogResult = DialogResult.Cancel };
            save.Click += (s, e) =>
            {
                day.EyeBlur = Picked(blur);
                day.Energy = Picked(energy);
                day.Save();
                DialogResult = DialogResult.OK;
                Close();
            };
            btns.Controls.AddRange(new Control[] { save, later });
            grid.Controls.Add(btns);
            Controls.Add(grid);
            AcceptButton = save;
            CancelButton = later;
        }

        static GroupBox Row(string title, string lo, string hi, RadioButton[] radios, int current)
        {
            var g = new GroupBox { Text = title, AutoSize = true, Dock = DockStyle.Fill, Padding = new Padding(10, 6, 10, 8) };
            var f = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
            f.Controls.Add(new Label { Text = lo, AutoSize = true, ForeColor = Color.Gray, Margin = new Padding(0, 6, 10, 0) });
            for (int i = 0; i < 5; i++)
            {
                radios[i] = new RadioButton { Text = (i + 1).ToString(), AutoSize = true, Checked = current == i + 1, Margin = new Padding(4, 3, 8, 0) };
                f.Controls.Add(radios[i]);
            }
            f.Controls.Add(new Label { Text = hi, AutoSize = true, ForeColor = Color.Gray, Margin = new Padding(6, 6, 0, 0) });
            g.Controls.Add(f);
            return g;
        }

        static int Picked(RadioButton[] r)
        {
            for (int i = 0; i < r.Length; i++) if (r[i].Checked) return i + 1;
            return 0;
        }
    }

    /// <summary>Plain monospace report window (today's stats, weekly summary).</summary>
    public class ReportForm : Form
    {
        public ReportForm(string title, string text)
        {
            Text = title;
            Icon = IconFactory.MakeIcon(IconFactory.Brand);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoSize = true; AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = new Padding(18);
            TopMost = true;
            Controls.Add(new Label { Text = text, Font = new Font("Consolas", 10.5f), AutoSize = true });
        }
    }

    /// <summary>30-day chart of eye blur, energy and break score: something to show your optometrist.</summary>
    public class TrendForm : Form
    {
        readonly List<DayStats> days;

        static readonly Color BlurColor = Color.FromArgb(232, 120, 40);
        static readonly Color EnergyColor = Color.FromArgb(30, 158, 138);
        static readonly Color ScoreColor = Color.FromArgb(215, 225, 232);

        public TrendForm(DayStats today)
        {
            Text = L.T("ScreenRest: health trend (last 30 days)", "ScreenRest: takbo ng kalusugan (huling 30 araw)");
            Icon = IconFactory.MakeIcon(IconFactory.Brand);
            StartPosition = FormStartPosition.CenterScreen;
            Size = new Size(900, 520);
            MinimumSize = new Size(600, 380);
            BackColor = Color.White;
            Font = new Font("Segoe UI", 9.5f);
            DoubleBuffered = true;
            ResizeRedraw = true;
            TopMost = true;

            days = new List<DayStats>();
            foreach (var d in DayStats.History(today))
                if (d.Date > DateTime.Today.AddDays(-30)) days.Add(d);

            var bottom = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 44, FlowDirection = FlowDirection.RightToLeft, Padding = new Padding(8) };
            var open = new Button { Text = L.T("Open data folder (CSV)", "Buksan ang data folder (CSV)"), AutoSize = true, Padding = new Padding(8, 2, 8, 2) };
            open.Click += (s, e) => { try { Process.Start("explorer.exe", DayStats.DataFolder); } catch { } };
            bottom.Controls.Add(open);
            Controls.Add(bottom);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            var area = new Rectangle(60, 50, ClientSize.Width - 110, ClientSize.Height - 150);
            using (var title = new Font("Segoe UI Semibold", 12f))
                g.DrawString(L.T("Right-eye blur and energy (1-5), with daily break score",
                                 "Labo ng kanang mata at lakas (1-5), kasama ang araw-araw na break score"), title, Brushes.Black, 56, 14);
            Legend(g, area.Right - 330, 40);

            if (days.Count == 0 || area.Width < 50 || area.Height < 50)
            {
                g.DrawString(L.T("No data yet. Do the daily check-in at the end of each shift.",
                                 "Wala pang data. Gawin ang check-in sa dulo ng bawat shift."), Font, Brushes.Gray, area.Left, area.Top + 20);
                return;
            }

            // Grid lines for ratings 1..5
            using (var gridPen = new Pen(Color.FromArgb(230, 234, 238)))
                for (int v = 1; v <= 5; v++)
                {
                    int y = RatingY(area, v);
                    g.DrawLine(gridPen, area.Left, y, area.Right, y);
                    g.DrawString(v.ToString(), Font, Brushes.Gray, area.Left - 22, y - 8);
                }

            DateTime start = DateTime.Today.AddDays(-29);
            float step = area.Width / 30f;
            // Break score as light bars: 0% at the bottom, 100% level with the "5" line (right-hand axis).
            int top = RatingY(area, 5);
            g.DrawString("100%", Font, Brushes.Gray, area.Right + 2, top - 8);
            g.DrawString("0%", Font, Brushes.Gray, area.Right + 2, area.Bottom - 14);
            using (var b = new SolidBrush(ScoreColor))
                foreach (var d in days)
                {
                    if (d.EyeTaken + d.EyeSkipped + d.StretchTaken + d.StretchSkipped == 0) continue;
                    float x = area.Left + (float)(d.Date - start).TotalDays * step;
                    float h = (area.Bottom - top) * d.Score / 100f;
                    g.FillRectangle(b, x + step * 0.2f, area.Bottom - h, step * 0.6f, h);
                }
            Line(g, area, start, step, BlurColor, true);
            Line(g, area, start, step, EnergyColor, false);

            // Date labels every 5 days
            for (int i = 0; i < 30; i += 5)
            {
                float x = area.Left + i * step;
                g.DrawString(L.Date(start.AddDays(i), "d MMM"), Font, Brushes.Gray, x, area.Bottom + 6);
            }
        }

        void Line(Graphics g, Rectangle area, DateTime start, float step, Color c, bool blurLine)
        {
            var pts = new List<PointF>();
            foreach (var d in days)
            {
                int v = blurLine ? d.EyeBlur : d.Energy;
                if (v <= 0) continue;
                pts.Add(new PointF(area.Left + (float)(d.Date - start).TotalDays * step + step / 2, RatingY(area, v)));
            }
            using (var pen = new Pen(c, 2.5f))
            using (var br = new SolidBrush(c))
            {
                if (pts.Count > 1) g.DrawLines(pen, pts.ToArray());
                foreach (var p in pts) g.FillEllipse(br, p.X - 4, p.Y - 4, 8, 8);
            }
        }

        static int RatingY(Rectangle area, int v) { return area.Bottom - (int)(area.Height * (v - 0.5) / 5.0); }

        void Legend(Graphics g, int x, int y)
        {
            Swatch(g, x, y, BlurColor, L.T("Eye blur", "Labo ng mata"));
            Swatch(g, x + 110, y, EnergyColor, L.T("Energy", "Lakas"));
            Swatch(g, x + 190, y, ScoreColor, "Break score");
        }

        void Swatch(Graphics g, int x, int y, Color c, string text)
        {
            using (var b = new SolidBrush(c)) g.FillRectangle(b, x, y + 4, 14, 10);
            g.DrawString(text, Font, Brushes.DimGray, x + 18, y);
        }
    }
}
