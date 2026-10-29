using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
namespace Nashi.Windows;
internal static class DesktopCapture
{
    [DllImport("user32.dll")]private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")]private static extern int ReleaseDC(IntPtr window,IntPtr dc);
    [DllImport("user32.dll")]private static extern int GetSystemMetrics(int metric);
    [DllImport("gdi32.dll")]private static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")]private static extern IntPtr CreateCompatibleBitmap(IntPtr dc,int width,int height);
    [DllImport("gdi32.dll")]private static extern IntPtr SelectObject(IntPtr dc,IntPtr item);
    [DllImport("gdi32.dll")]private static extern bool BitBlt(IntPtr target,int x,int y,int width,int height,IntPtr source,int sx,int sy,uint operation);
    [DllImport("gdi32.dll")]private static extern bool DeleteObject(IntPtr item);
    [DllImport("gdi32.dll")]private static extern bool DeleteDC(IntPtr dc);
    internal static void Save(string file)
    {
        // Explicit test mode only: captures the isolated CI desktop containing
        // synthetic Nashi fixtures, never the user's normal session.
        if(!App.IsSmokeTest)return;var width=GetSystemMetrics(0);var height=GetSystemMetrics(1);var screen=GetDC(IntPtr.Zero);var memory=CreateCompatibleDC(screen);var bitmap=CreateCompatibleBitmap(screen,width,height);var original=SelectObject(memory,bitmap);
        try{if(BitBlt(memory,0,0,width,height,screen,0,0,0x40cc0020))ImageEngine.Save(Imaging.CreateBitmapSourceFromHBitmap(bitmap,IntPtr.Zero,Int32Rect.Empty,System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions()),file,"png");}finally{SelectObject(memory,original);DeleteObject(bitmap);DeleteDC(memory);ReleaseDC(IntPtr.Zero,screen);}
    }
}
