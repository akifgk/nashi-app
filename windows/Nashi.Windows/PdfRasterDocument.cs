using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace Nashi.Windows;

// CPU-only PDF rasterization. Keep native PDF objects and their pinned source
// bytes together, and serialize PDFium (its public API is not thread-safe).
internal sealed class PdfRasterDocument:IDisposable
{
    private static readonly object gate=new();private static bool initialized;private static int documents;
    private nint document;private GCHandle source;private PdfFormPreview? form;
    internal int PageCount{get;}
    internal static int OpenDocuments{get{lock(gate)return documents;}}
    private PdfRasterDocument(string path,string password)
    {
        using var input=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);var length=input.Length;if(length<1||length>200_000_000)throw new InvalidDataException("Choose a PDF smaller than 200 MB.");
        var data=new byte[checked((int)length)];input.ReadExactly(data);
        lock(gate)
        {
            if(!initialized){Native.FPDF_InitLibrary();initialized=true;}
            source=GCHandle.Alloc(data,GCHandleType.Pinned);
            try
            {
                document=Native.FPDF_LoadMemDocument64(source.AddrOfPinnedObject(),(nuint)data.LongLength,password);
                if(document==0)throw new InvalidDataException(Native.FPDF_GetLastError()==4?"The PDF password is missing or incorrect.":"This PDF could not be opened.");
                PageCount=Native.FPDF_GetPageCount(document);
                if(PageCount<1||PageCount>1000)throw new InvalidDataException("Choose a PDF with 1 to 1,000 pages.");
                if(Native.FPDF_GetFormType(document)!=0)form=new PdfFormPreview(document);
                documents++;
            }
            catch{form?.Dispose();if(document!=0){Native.FPDF_CloseDocument(document);document=0;}if(source.IsAllocated)source.Free();throw;}
        }
    }
    internal static PdfRasterDocument Open(string path,string password="")=>new(path,password);
    internal byte[] RenderPage(int index,int dpi,CancellationToken token)
    {
        token.ThrowIfCancellationRequested();if(dpi<36||dpi>600)throw new ArgumentOutOfRangeException(nameof(dpi));
        lock(gate)
        {
            ObjectDisposedException.ThrowIf(document==0,this);
            if(index<0||index>=PageCount)throw new ArgumentOutOfRangeException(nameof(index));
            var page=Native.FPDF_LoadPage(document,index);if(page==0)throw new InvalidDataException("This PDF page could not be read.");
            try
            {
                form?.Load(page,index);
                var w=Native.FPDF_GetPageWidth(page)*dpi/72;var h=Native.FPDF_GetPageHeight(page)*dpi/72;
                if(!double.IsFinite(w)||!double.IsFinite(h)||w<1||h<1||w*h>100_000_000)throw new InvalidDataException("PDF page exceeds 100 MP.");
                var width=checked((int)Math.Ceiling(w));var height=checked((int)Math.Ceiling(h));if((long)width*height>100_000_000)throw new InvalidDataException("PDF page exceeds 100 MP.");var stride=checked(width*4);var pixels=new byte[checked(stride*height)];
                var pinned=GCHandle.Alloc(pixels,GCHandleType.Pinned);nint bitmap=0;
                try
                {
                    bitmap=Native.FPDFBitmap_CreateEx(width,height,4,pinned.AddrOfPinnedObject(),stride);
                    if(bitmap==0)throw new InvalidDataException("PDF preview bitmap could not be allocated.");
                    if(Native.FPDFBitmap_FillRect(bitmap,0,0,width,height,0xffffffff)==0)throw new InvalidDataException("PDF preview background could not be prepared.");
                    Native.FPDF_RenderPageBitmap(bitmap,page,0,0,width,height,0,1);form?.Draw(bitmap,width,height);token.ThrowIfCancellationRequested();
                    return ImageEngine.PngBytes(BitmapSource.Create(width,height,dpi,dpi,PixelFormats.Bgra32,null,pixels,stride));
                }
                finally{if(bitmap!=0)Native.FPDFBitmap_Destroy(bitmap);pinned.Free();}
            }
            finally{form?.ClosePage();Native.FPDF_ClosePage(page);}
        }
    }
    public void Dispose(){lock(gate){if(document==0)return;form?.Dispose();form=null;Native.FPDF_CloseDocument(document);document=0;documents--;if(source.IsAllocated)source.Free();}GC.SuppressFinalize(this);}
    ~PdfRasterDocument(){Dispose();}
    internal static void Shutdown(){lock(gate){if(initialized&&documents==0){Native.FPDF_DestroyLibrary();initialized=false;}}}
    private static class Native
    {
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FPDF_InitLibrary();
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FPDF_DestroyLibrary();
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern nint FPDF_LoadMemDocument64(nint data,nuint size,[MarshalAs(UnmanagedType.LPUTF8Str)]string password);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern uint FPDF_GetLastError();
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern int FPDF_GetPageCount(nint document);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern int FPDF_GetFormType(nint document);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern nint FPDF_LoadPage(nint document,int index);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern double FPDF_GetPageWidth(nint page);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern double FPDF_GetPageHeight(nint page);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern nint FPDFBitmap_CreateEx(int width,int height,int format,nint data,int stride);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern int FPDFBitmap_FillRect(nint bitmap,int left,int top,int width,int height,uint color);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FPDF_RenderPageBitmap(nint bitmap,nint page,int left,int top,int width,int height,int rotate,int flags);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FPDFBitmap_Destroy(nint bitmap);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FPDF_ClosePage(nint page);
        [DllImport("pdfium",CallingConvention=CallingConvention.Winapi)]internal static extern void FPDF_CloseDocument(nint document);
    }
}
