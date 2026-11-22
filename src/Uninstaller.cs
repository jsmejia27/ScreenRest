using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
using Microsoft.Win32;

namespace ScreenRest
{
    /// <summary>
    /// "ScreenRest.exe --uninstall", registered by Setup as the uninstall command in Windows Settings > Apps.
    /// Removes shortcuts, the startup entry and the Apps entry, optionally your data, then the install folder.
    /// </summary>
    public static class Uninstaller
    {
        public const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ScreenRest";

        public static void Run()
        {
            string caption = L.T("Uninstall ScreenRest", "I-uninstall ang ScreenRest");
            if (MessageBox.Show(L.T("Remove ScreenRest from this PC?", "Tanggalin ang ScreenRest sa PC na ito?"), caption,
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;

            // Stop the running tray app so its files can be removed.
            int me = Process.GetCurrentProcess().Id;
            foreach (var p in Process.GetProcessesByName("ScreenRest"))
            {
                if (p.Id == me) continue;
                try { p.Kill(); p.WaitForExit(3000); } catch { }
            }

            try { Settings.StartupEnabled = false; } catch { }
            TryDelete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "ScreenRest.lnk"));
            TryDelete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "ScreenRest.lnk"));
            try { Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false); } catch { }

            if (Directory.Exists(Settings.Dir) &&
                MessageBox.Show(L.T("Also delete your ScreenRest settings and break history?",
                                    "Burahin din ba ang iyong ScreenRest settings at kasaysayan ng breaks?") + "\n\n" + Settings.Dir,
                    caption, MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.Yes)
            {
                try { Directory.Delete(Settings.Dir, true); } catch { }
            }

            // Remove the install folder once this process has exited, but only if it really is ScreenRest's own folder.
            string dir = Path.GetDirectoryName(Application.ExecutablePath);
            bool ownFolder = string.Equals(Path.GetFileName(dir), "ScreenRest", StringComparison.OrdinalIgnoreCase)
                             && File.Exists(Path.Combine(dir, "ScreenRest.exe"));
            if (ownFolder)
            {
                try
                {
                    Process.Start(new ProcessStartInfo("cmd.exe",
                        "/c ping -n 3 127.0.0.1 >nul & rmdir /s /q \"" + dir + "\"")
                    { CreateNoWindow = true, UseShellExecute = false, WorkingDirectory = Path.GetTempPath() });
                }
                catch { }
            }
            MessageBox.Show(L.T("ScreenRest has been removed. Take care of your eyes!",
                                "Natanggal na ang ScreenRest. Ingatan ang iyong mga mata!"), caption,
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        static void TryDelete(string f) { try { if (File.Exists(f)) File.Delete(f); } catch { } }
    }
}
