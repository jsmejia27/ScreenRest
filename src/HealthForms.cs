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
}
