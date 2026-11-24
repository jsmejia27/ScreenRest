using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("ScreenRest Setup")]
[assembly: AssemblyProduct("ScreenRest")]
[assembly: AssemblyDescription("Installs ScreenRest for the current user")]
[assembly: AssemblyCompany("Jilbert Mejia")]
[assembly: AssemblyCopyright("© 2026 Jilbert Mejia. MIT License.")]
[assembly: AssemblyVersion("1.2.0.0")]
[assembly: AssemblyFileVersion("1.2.0.0")]

namespace ScreenRest.Setup
{
    /// <summary>
    /// One-file per-user installer. The app (exe + media) is embedded as payload.zip.
    /// Installs to %LOCALAPPDATA%\Programs\ScreenRest, so no administrator rights are needed.
    /// </summary>
    public class SetupForm : Form
    {
        public const string Version = "1.2.0";
        const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ScreenRest";

        static readonly Color Bg = Color.FromArgb(14, 22, 28);
        static readonly Color Panel2 = Color.FromArgb(22, 32, 40);
        static readonly Color Accent = Color.FromArgb(70, 205, 180);
        static readonly Color Brand = Color.FromArgb(30, 158, 138);
        static readonly Color Soft = Color.FromArgb(200, 212, 220);
        static readonly Color Dim = Color.FromArgb(130, 145, 155);

        public static string InstallDir
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ScreenRest"); }
        }

        readonly Label status;
        readonly ProgressBar progress;
        readonly CheckBox chkStartup, chkDesktop, chkLaunch;
        readonly Button btnInstall, btnCancel;
        bool done;

        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
        }

        public SetupForm()
        {
            Text = "ScreenRest Setup";
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(560, 432);
            BackColor = Bg;
            ForeColor = Soft;
            Font = new Font("Segoe UI", 10.5f);

            var logo = new PictureBox { Image = ScreenRest.IconFactory.Draw(64, Brand), Size = new Size(64, 64), Location = new Point(32, 28) };
            var title = new Label { Text = "ScreenRest", ForeColor = Color.White, Font = new Font("Segoe UI Semibold", 22f), AutoSize = true, Location = new Point(108, 26) };
            var sub = new Label { Text = "Rest your eyes. Move your body.  ·  Version " + Version, ForeColor = Accent, AutoSize = true, Location = new Point(112, 68) };

            var info = new Label
            {
                Text = "ScreenRest reminds you to look away from the screen every 20 minutes and to stand up and " +
                       "stretch every hour, guided by short videos and a calm voice. English or Tagalog. Free, private, no account.",
                AutoSize = false, Size = new Size(496, 64), Location = new Point(32, 116)
            };
            var where = new Label
            {
                Text = "Installs for you only (no administrator rights needed) to:\n" + InstallDir,
                ForeColor = Dim, AutoSize = false, Size = new Size(496, 44), Location = new Point(32, 186), Font = new Font("Segoe UI", 9.5f)
            };

            chkStartup = MakeCheck("Start ScreenRest when I sign in to Windows (recommended)", 240);
            chkDesktop = MakeCheck("Add a desktop shortcut", 268);
            chkLaunch = MakeCheck("Open ScreenRest when setup finishes", 296);
            chkDesktop.Checked = false;

            progress = new ProgressBar { Location = new Point(32, 336), Size = new Size(496, 6), Visible = false };
            status = new Label { ForeColor = Dim, AutoSize = false, Size = new Size(300, 40), Location = new Point(32, 358), Font = new Font("Segoe UI", 9.5f) };

            btnInstall = MakeButton("Install", true, new Point(440, 358));
            btnCancel = MakeButton("Cancel", false, new Point(342, 358));
            btnInstall.Click += (o, e) => { if (done) Close(); else DoInstall(); };
            btnCancel.Click += (o, e) => Close();

            var copy = new Label { Text = "© 2026 Jilbert Mejia. MIT License.", ForeColor = Dim, AutoSize = true,
                                   Location = new Point(32, 406), Font = new Font("Segoe UI", 8.5f) };

            Controls.AddRange(new Control[] { logo, title, sub, info, where, chkStartup, chkDesktop, chkLaunch, progress, status, btnInstall, btnCancel, copy });
            AcceptButton = btnInstall;
            CancelButton = btnCancel;

            if (File.Exists(Path.Combine(InstallDir, "ScreenRest.exe")))
            {
                btnInstall.Text = "Update";
                status.Text = "Already installed. Your settings and history are kept.";
            }
        }

        CheckBox MakeCheck(string text, int y)
        {
            return new CheckBox { Text = text, Checked = true, AutoSize = true, Location = new Point(32, y), ForeColor = Soft };
        }

        Button MakeButton(string text, bool primary, Point at)
        {
            var b = new Button
            {
                Text = text, Location = at, Size = new Size(88, 34), FlatStyle = FlatStyle.Flat, Cursor = Cursors.Hand,
                BackColor = primary ? Brand : Panel2, ForeColor = primary ? Color.White : Soft, Font = new Font("Segoe UI Semibold", 10.5f)
            };
            b.FlatAppearance.BorderColor = primary ? Brand : Color.FromArgb(60, 78, 90);
            return b;
        }

        void DoInstall()
        {
            btnInstall.Enabled = btnCancel.Enabled = false;
            chkStartup.Enabled = chkDesktop.Enabled = chkLaunch.Enabled = false;
            progress.Visible = true;
            try
            {
                status.Text = "Closing ScreenRest if it's running...";
                Application.DoEvents();
                StopRunningApp();

                status.Text = "Copying files...";
                Extract(InstallDir, (i, n) => { progress.Maximum = n; progress.Value = i; Application.DoEvents(); });

                string exe = Path.Combine(InstallDir, "ScreenRest.exe");
                CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "ScreenRest.lnk"), exe);
                if (chkDesktop.Checked)
                    CreateShortcut(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "ScreenRest.lnk"), exe);
                SetStartup(exe, chkStartup.Checked);
                RegisterUninstall(exe);

                done = true;
                status.Text = "Done. Look for the green eye icon near the clock.";
                btnInstall.Text = "Finish";
                btnInstall.Enabled = true;
                if (chkLaunch.Checked) Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = InstallDir });
            }
            catch (Exception ex)
            {
                MessageBox.Show(this, "Setup could not finish:\n\n" + ex.Message, "ScreenRest Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
                btnInstall.Enabled = btnCancel.Enabled = true;
                status.Text = "";
            }
        }

        static void StopRunningApp()
        {
            foreach (var p in Process.GetProcessesByName("ScreenRest"))
            {
                try { p.Kill(); p.WaitForExit(3000); } catch { }
            }
        }

        /// <summary>Unpacks the embedded payload.zip into dir (overwriting older files). Returns the entry count.</summary>
        public static int Extract(string dir, Action<int, int> onProgress)
        {
            Directory.CreateDirectory(dir);
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (s == null) throw new InvalidOperationException("Installer payload is missing.");
                using (var zip = new ZipArchive(s, ZipArchiveMode.Read))
                {
                    int i = 0, n = zip.Entries.Count;
                    string root = Path.GetFullPath(dir).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                    foreach (var entry in zip.Entries)
                    {
                        string target = Path.GetFullPath(Path.Combine(dir, entry.FullName));
                        if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue; // no path escapes
                        if (entry.FullName.EndsWith("/")) Directory.CreateDirectory(target);
                        else
                        {
                            Directory.CreateDirectory(Path.GetDirectoryName(target));
                            using (var src = entry.Open())
                            using (var dst = File.Create(target)) src.CopyTo(dst);
                        }
                        i++;
                        if (onProgress != null) onProgress(i, n);
                    }
                    return n;
                }
            }
        }

        static void CreateShortcut(string lnkPath, string exe)
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            object shell = Activator.CreateInstance(t);
            object lnk = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnkPath });
            Type lt = lnk.GetType();
            lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, lnk, new object[] { exe });
            lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, lnk, new object[] { Path.GetDirectoryName(exe) });
            lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, lnk, new object[] { exe + ",0" });
            lt.InvokeMember("Description", BindingFlags.SetProperty, null, lnk, new object[] { "Eye and stretch break reminders" });
            lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, lnk, null);
        }

        static void SetStartup(string exe, bool on)
        {
            using (var k = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
            {
                if (on) k.SetValue("ScreenRest", "\"" + exe + "\"");
                else if (k.GetValue("ScreenRest") != null) k.DeleteValue("ScreenRest");
            }
        }

        static void RegisterUninstall(string exe)
        {
            long kb = 0;
            foreach (var f in Directory.GetFiles(InstallDir, "*", SearchOption.AllDirectories)) kb += new FileInfo(f).Length / 1024;
            using (var k = Registry.CurrentUser.CreateSubKey(UninstallKey))
            {
                k.SetValue("DisplayName", "ScreenRest");
                k.SetValue("DisplayVersion", Version);
                k.SetValue("Publisher", "Jilbert Mejia");
                k.SetValue("DisplayIcon", exe + ",0");
                k.SetValue("InstallLocation", InstallDir);
                k.SetValue("UninstallString", "\"" + exe + "\" --uninstall");
                k.SetValue("EstimatedSize", (int)kb, RegistryValueKind.DWord);
                k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }
        }
    }
}
