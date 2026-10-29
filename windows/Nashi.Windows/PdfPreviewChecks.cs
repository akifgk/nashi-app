using System.Text;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace Nashi.Windows;

internal static class PdfPreviewChecks
{
    internal static void Run(string root,Action<bool,string> check)
    {
        // A blank page whose only visible text is the AcroForm appearance.
        // Rendering page contents alone silently loses this field value.
        const string appearance="q 1 1 1 rg 0 0 240 50 re f 0 g BT /F1 20 Tf 10 16 Td (NASHI FORM) Tj ET Q";
        var objects=new[]{"<< /Type /Catalog /Pages 2 0 R /AcroForm 6 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 150] /Annots [5 0 R] /Resources << /Font << /F1 4 0 R >> >> /Contents 7 0 R >>","<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>","<< /Type /Annot /Subtype /Widget /FT /Tx /T (Name) /V (NASHI FORM) /Rect [30 50 270 100] /F 4 /AP << /N 8 0 R >> /P 3 0 R >>","<< /Fields [5 0 R] /DA (/F1 20 Tf 0 g) /DR << /Font << /F1 4 0 R >> >> >>","<< /Length 0 >>\nstream\n\nendstream","<< /Type /XObject /Subtype /Form /BBox [0 0 240 50] /Resources << /Font << /F1 4 0 R >> >> /Length "+appearance.Length+" >>\nstream\n"+appearance+"\nendstream"};
        using var output=new MemoryStream();void Write(string text){var bytes=Encoding.ASCII.GetBytes(text);output.Write(bytes);}Write("%PDF-1.4\n");var offsets=new List<long>{0};
        for(var n=0;n<objects.Length;n++){offsets.Add(output.Position);Write($"{n+1} 0 obj\n{objects[n]}\nendobj\n");}
        var xref=output.Position;Write($"xref\n0 {offsets.Count}\n0000000000 65535 f \n");foreach(var offset in offsets.Skip(1))Write(offset.ToString("D10",System.Globalization.CultureInfo.InvariantCulture)+" 00000 n \n");Write($"trailer\n<< /Size {offsets.Count} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n");
        var path=Path.Combine(root,"PDF form preview.pdf");File.WriteAllBytes(path,output.ToArray());
        using(var pdf=PdfRasterDocument.Open(path))
        {
            var image=ImageEngine.FromPng(pdf.RenderPage(0,72,CancellationToken.None));check(image.PixelWidth==300&&image.PixelHeight==150,"PDF preview lost page dimensions");
            var pixels=new byte[240*50*4];new FormatConvertedBitmap(image,PixelFormats.Bgra32,null,0).CopyPixels(new Int32Rect(30,50,240,50),pixels,240*4,0);check(pixels.Where((value,index)=>index%4==0&&value<100).Count()>100,"Read-only PDF preview omitted AcroForm field appearances");
        }
        using(var reopened=PdfRasterDocument.Open(path)){using var cancelled=new CancellationTokenSource();cancelled.Cancel();try{reopened.RenderPage(0,72,cancelled.Token);throw new Exception("Cancelled PDF render continued");}catch(OperationCanceledException){check(true,"PDF render cancellation retained its lifecycle");}}
        var corrupt=Path.Combine(root,"Invalid PDF.pdf");File.WriteAllText(corrupt,"Not a PDF");try{using var invalid=PdfRasterDocument.Open(corrupt);throw new Exception("Invalid PDF was accepted");}catch(InvalidDataException){check(true,"Invalid PDF preview failed safely");}
        check(PdfRasterDocument.OpenDocuments==0,"PDF render/error paths leaked documents or pinned input");
    }
}
