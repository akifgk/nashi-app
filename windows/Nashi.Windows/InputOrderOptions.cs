using System.Windows;
using System.Windows.Controls;
namespace Nashi.Windows;
public sealed partial class ToolEditor
{
    private readonly ListBox inputOrder=new(){MaxHeight=340};
    internal string[] OrderedInputs{get;private set;}=[];
    private void BuildInputOrder(IReadOnlyList<string> inputs)
    {
        OrderedInputs=inputs.ToArray();if(tool is not ("joinVideos" or "mergePDFs" or "createPDF"))return;
        options.Children.Add(L10n.Label(new TextBlock{Text="File order",Margin=new(4,12,4,4)}));foreach(var path in inputs)inputOrder.Items.Add(new ListBoxItem{Content=tool=="createPDF"?OrderRow(path):Path.GetFileName(path),Tag=path});options.Children.Add(inputOrder);
        void Move(int delta){var i=inputOrder.SelectedIndex;var next=i+delta;if(i<0||next<0||next>=inputOrder.Items.Count)return;var item=inputOrder.Items[i];inputOrder.Items.RemoveAt(i);inputOrder.Items.Insert(next,item);inputOrder.SelectedIndex=next;OrderedInputs=inputOrder.Items.Cast<ListBoxItem>().Select(x=>(string)x.Tag).ToArray();}
        var buttons=new WrapPanel();buttons.Children.Add(MainWindow.Button("Move up",()=>Move(-1)));buttons.Children.Add(MainWindow.Button("Move down",()=>Move(1)));options.Children.Add(buttons);
        if(tool is "createPDF" or "mergePDFs")
        {
            options.Children.Add(L10n.Label(new TextBlock{Text="File name",Margin=new(4,12,4,4)}));
            outputName.ToolTip=L10n.Text("Without .pdf. Leave empty for the default name.");options.Children.Add(outputName);
        }
    }
    private readonly TextBox outputName=new();
    /// The name typed for the combined PDF, or null for the default.
    internal string? OutputName=>string.IsNullOrWhiteSpace(outputName.Text)?null:outputName.Text;
    // A small preview next to the name, so every selected image is visible while ordering a PDF.
    private static FrameworkElement OrderRow(string path)
    {
        var row=new StackPanel{Orientation=Orientation.Horizontal};
        try
        {
            var thumbnail=new System.Windows.Media.Imaging.BitmapImage();thumbnail.BeginInit();thumbnail.UriSource=new Uri(path);thumbnail.DecodePixelWidth=72;thumbnail.CacheOption=System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;thumbnail.EndInit();thumbnail.Freeze();
            row.Children.Add(new System.Windows.Controls.Image{Source=thumbnail,Width=36,Height=36,Stretch=System.Windows.Media.Stretch.UniformToFill,Margin=new(0,2,10,2)});
        }
        catch(Exception error)when(error is NotSupportedException or IOException or InvalidOperationException or UnauthorizedAccessException or FileFormatException){}
        row.Children.Add(new TextBlock{Text=Path.GetFileName(path),VerticalAlignment=VerticalAlignment.Center});return row;
    }
}
