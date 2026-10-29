using System.Runtime.InteropServices;
namespace Nashi.Windows;

// CI-only native exception observer for the explicit, isolated smoke fixture.
// The optional DLL is built from windows/Diagnostics; never shipped in the app.
internal static class NativeExceptionTrace
{
    private static nint library;
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate void InstallTrace();
    internal static void Install()
    {
        if(!App.IsSmokeTest||Environment.GetEnvironmentVariable("GITHUB_ACTIONS")!="true"||Environment.GetEnvironmentVariable("NASHI_NATIVE_TRACE_LIBRARY") is not {} path)return;
        library=NativeLibrary.Load(Path.GetFullPath(path));
        Marshal.GetDelegateForFunctionPointer<InstallTrace>(NativeLibrary.GetExport(library,"InstallTrace"))();
        // Keep the observer resident through native shutdown. It only records
        // exception stacks; it never handles or changes an exception/result.
    }
}
