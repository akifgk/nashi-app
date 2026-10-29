using System.Runtime.InteropServices;
namespace Nashi.Windows;

// Read-only AcroForm appearance rendering. No JavaScript platform, URI actions,
// focus events or timers are supplied to a preview document.
internal sealed class PdfFormPreview:IDisposable
{
    private nint info,page;private int pageIndex;private readonly nint document;private readonly Delegate[] callbacks;
    internal nint Handle{get;private set;}
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate void Invalidate(nint self,nint page,double left,double top,double right,double bottom);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate void Cursor(nint self,int cursor);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate int Timer(nint self,int milliseconds,nint callback);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate void KillTimer(nint self,int id);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate SystemTime LocalTime(nint self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate void Change(nint self);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate nint GetPage(nint self,nint document,int index);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate nint CurrentPage(nint self,nint document);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]private delegate int Rotation(nint self,nint page);
    [StructLayout(LayoutKind.Sequential)]private struct SystemTime{public ushort Year,Month,DayOfWeek,Day,Hour,Minute,Second,Milliseconds;}
    // Exact version-1 prefix from the pinned PDFium fpdf_formfill.h. All
    // callbacks remain rooted until ExitFormFillEnvironment returns.
    [StructLayout(LayoutKind.Sequential)]private struct FormInfo
    {
        public int Version;
        public nint Release,Invalidate,OutputSelectedRect,SetCursor,SetTimer,KillTimer,GetLocalTime,OnChange,GetPage,GetCurrentPage,GetRotation,ExecuteNamedAction,SetTextFieldFocus,DoUriAction,DoGoToAction,JsPlatform;
    }
    internal PdfFormPreview(nint document)
    {
        this.document=document;
        callbacks=[new Invalidate((_,_,_,_,_,_)=>{}),new Cursor((_,_)=>{}),new Timer((_,_,_)=>-1),new KillTimer((_,_)=>{}),new LocalTime(_=>default),new Change(_=>{}),
            new GetPage((_,doc,index)=>doc==this.document&&index==pageIndex?page:0),new CurrentPage((_,doc)=>doc==this.document?page:0),new Rotation((_,_)=>0)];
        nint Pointer(int index)=>Marshal.GetFunctionPointerForDelegate(callbacks[index]);
        var value=new FormInfo{Version=1,Invalidate=Pointer(0),SetCursor=Pointer(1),SetTimer=Pointer(2),KillTimer=Pointer(3),GetLocalTime=Pointer(4),OnChange=Pointer(5),GetPage=Pointer(6),GetCurrentPage=Pointer(7),GetRotation=Pointer(8)};
        info=Marshal.AllocHGlobal(Marshal.SizeOf<FormInfo>());Marshal.StructureToPtr(value,info,false);Handle=Native.FPDFDOC_InitFormFillEnvironment(document,info);
        if(Handle==0){Marshal.FreeHGlobal(info);info=0;throw new InvalidDataException("PDF form appearances could not be prepared.");}
    }
    internal void Load(nint value,int index){page=value;pageIndex=index;Native.FORM_OnAfterLoadPage(page,Handle);}
    internal void Draw(nint bitmap,int width,int height)=>Native.FPDF_FFLDraw(Handle,bitmap,page,0,0,width,height,0,1);
    internal void ClosePage(){if(page!=0)Native.FORM_OnBeforeClosePage(page,Handle);page=0;}
    public void Dispose(){if(Handle==0)return;ClosePage();Native.FPDFDOC_ExitFormFillEnvironment(Handle);Handle=0;Marshal.FreeHGlobal(info);info=0;GC.KeepAlive(callbacks);}
    private static class Native
    {
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern nint FPDFDOC_InitFormFillEnvironment(nint document,nint info);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FPDFDOC_ExitFormFillEnvironment(nint handle);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FORM_OnAfterLoadPage(nint page,nint handle);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FORM_OnBeforeClosePage(nint page,nint handle);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FPDF_FFLDraw(nint handle,nint bitmap,nint page,int x,int y,int width,int height,int rotate,int flags);
    }
}
