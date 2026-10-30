using System.IO;
using System.Windows;
using Nashi.Core;
namespace Nashi.Windows;

public sealed partial class MainWindow
{
    /// Crop, cover and annotate with several images selected: each image opens in its own editor
    /// ("Crop Image 2/3"), so every one keeps its own area or drawing. Cancel at any step cancels all.
    private async Task EditImagesOneByOneAsync(ToolChoice choice,string[] selected)
    {
        var settings=new List<ImageOptions>();
        for(var n=0;n<selected.Length;n++)
        {
            var file=selected[n];var editor=new ToolEditor(this,choice.Id,choice.Title,file,null,ImageEngine.Load(file),[file],null);
            editor.ConfigureProfiles(preferences,null);editor.ConfigureMediaRuntime(tools);
            editor.Title=L10n.Text(choice.Title)+" "+(n+1)+"/"+selected.Length+" · Nashi";
            if(editor.ShowDialog()!=true)return;
            settings.Add(editor.ImageOptions);
        }
        var encoder=tools.Ready?tools.Executable("ffmpeg"):null;
        await RunAsync(async(destination,p,t)=>
        {
            using var tx=new ExportTransaction(destination);var exported=new List<string>();
            for(var n=0;n<selected.Length;n++)
            {
                var index=n;t.ThrowIfCancellationRequested();
                exported.AddRange(await OnStaAsync(()=>ImageEngine.Apply(choice.Id,[selected[index]],tx.StagingDirectory,settings[index] with{EncoderPath=encoder},null,t,null)));
                p.Report(new((index+1d)/selected.Length*.95,$"{index+1} / {selected.Length}"));
            }
            return tx.Publish(exported,t);
        },choice.Title);
    }
}
