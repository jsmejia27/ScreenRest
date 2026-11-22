using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace ScreenRest
{
    static class Program
    {
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main(string[] args)
        {
            bool demo = false;
            try { L.Set(Settings.Load().Language); } catch { }
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--demo") demo = true;
                if (args[i] == "--make-icon" && i + 1 < args.Length) { IconFactory.SaveIco(args[i + 1]); return; }
                if (args[i] == "--uninstall") { Application.EnableVisualStyles(); Uninstaller.Run(); return; }
            }

            bool created;
            using (var mutex = new Mutex(true, @"Local\ScreenRest_SingleInstance", out created))
            {
                if (!created)
                {
                    MessageBox.Show(L.T("ScreenRest is already running. Look for the eye icon in the system tray near the clock.",
                        "Tumatakbo na ang ScreenRest. Hanapin ang icon na mata sa system tray, malapit sa orasan."),
                        "ScreenRest", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }
                try { SetProcessDPIAware(); } catch { }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayApp(demo));
            }
        }
    }
}
