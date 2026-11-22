using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace ScreenRest
{
    /// <summary>Windows queries: idle time, "am I in a meeting / presenting / full-screen?"</summary>
    public static class Native
    {
        // ---------------------------------------------------------------- idle time
        [StructLayout(LayoutKind.Sequential)]
        struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

        /// <summary>Seconds since the last keyboard or mouse input (any app).</summary>
        public static int IdleSeconds()
        {
            return (int)(IdleMilliseconds() / 1000);
        }

        public static uint IdleMilliseconds()
        {
            var li = new LASTINPUTINFO();
            li.cbSize = (uint)Marshal.SizeOf(li);
            if (!GetLastInputInfo(ref li)) return 0;
            return unchecked((uint)Environment.TickCount - li.dwTime);
        }

        // ---------------------------------------------------------------- busy detection
        [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }

        const int QUNS_BUSY = 2, QUNS_RUNNING_D3D_FULL_SCREEN = 3, QUNS_PRESENTATION_MODE = 4;

        /// <summary>
        /// True when a break would be rude: camera/microphone in use (video call), presentation mode,
        /// or a full-screen app (slideshow, video, game) is in front. <paramref name="reason"/> says which.
        /// </summary>
        public static bool IsBusy(out string reason)
        {
            reason = null;
            if (DeviceInUse("webcam")) { reason = L.T("your camera is on", "nakabukas ang camera mo"); return true; }
            if (DeviceInUse("microphone")) { reason = L.T("you're on a call", "nasa tawag ka"); return true; }

            try
            {
                int st;
                if (SHQueryUserNotificationState(out st) == 0 &&
                    (st == QUNS_BUSY || st == QUNS_RUNNING_D3D_FULL_SCREEN || st == QUNS_PRESENTATION_MODE))
                { reason = st == QUNS_PRESENTATION_MODE ? L.T("you're presenting", "nagpe-present ka") : L.T("a full-screen app is open", "may bukas na full-screen app"); return true; }
            }
            catch { }

            if (ForegroundIsFullScreen()) { reason = L.T("a full-screen app is open", "may bukas na full-screen app"); return true; }
            return false;
        }

        static bool ForegroundIsFullScreen()
        {
            IntPtr h = GetForegroundWindow();
            if (h == IntPtr.Zero) return false;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (pid == (uint)System.Diagnostics.Process.GetCurrentProcess().Id) return false; // our own break screen
            var cls = new StringBuilder(64);
            GetClassName(h, cls, cls.Capacity);
            string c = cls.ToString();
            if (c == "Progman" || c == "WorkerW" || c == "Shell_TrayWnd") return false; // desktop / taskbar
            RECT r;
            if (!GetWindowRect(h, out r)) return false;
            var scr = System.Windows.Forms.Screen.FromHandle(h).Bounds;
            return r.Left <= scr.Left && r.Top <= scr.Top && r.Right >= scr.Right && r.Bottom >= scr.Bottom;
        }

        /// <summary>
        /// Windows records camera/mic use per app under CapabilityAccessManager\ConsentStore.
        /// An entry with LastUsedTimeStart set and LastUsedTimeStop = 0 is in use right now.
        /// </summary>
        static bool DeviceInUse(string capability)
        {
            try
            {
                using (var root = Registry.CurrentUser.OpenSubKey(
                    @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\" + capability))
                {
                    if (root == null) return false;
                    foreach (var name in root.GetSubKeyNames())
                    {
                        using (var k = root.OpenSubKey(name))
                        {
                            if (k == null) continue;
                            if (name == "NonPackaged")
                            {
                                foreach (var sub in k.GetSubKeyNames())
                                    using (var s = k.OpenSubKey(sub))
                                        if (InUse(s)) return true;
                            }
                            else if (InUse(k)) return true;
                        }
                    }
                }
            }
            catch { }
            return false;
        }

        static bool InUse(RegistryKey k)
        {
            if (k == null) return false;
            object start = k.GetValue("LastUsedTimeStart"), stop = k.GetValue("LastUsedTimeStop");
            if (start == null || stop == null) return false;
            return Convert.ToInt64(start) > 0 && Convert.ToInt64(stop) == 0;
        }
    }
}
