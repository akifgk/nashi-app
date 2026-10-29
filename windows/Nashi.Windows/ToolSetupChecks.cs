using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Nashi.Core;
namespace Nashi.Windows;
internal static class ToolSetupChecks
{
    internal static void Run(string output,Window owner,Action<bool,string> check)
    {
        var current=new ToolSetupStatus(false,false);var media=0;var office=0;var mode=0;var language=L10n.Language;
        var setup=new ToolSetupWindow(owner,()=>current,async (group,progress,token)=>
        {
            if(group==ToolGroup.Media){media++;current=current with{MediaReady=true};progress.Report(new(1,"Media tools ready"));}
            else
            {
                office++;
                if(mode==0)throw new IOException("Offline fixture: retry setup.");
                if(mode==1)await Task.Delay(Timeout.Infinite,token);
                current=current with{OfficeReady=true};progress.Report(new(1,"Office tools ready"));
            }
        });
        void WaitIdle(){var end=DateTime.UtcNow.AddSeconds(5);while(setup.Working&&DateTime.UtcNow<end)DesktopInput.Pump();check(!setup.Working,"Setup did not return to a retryable state");DesktopInput.Pump();}
        void PressContinue(){setup.ContinueButton.Focus();DesktopInput.Key(setup,Key.Enter);}
        try
        {
            L10n.Language="en";setup.Show();DesktopInput.Pump();
            check(!setup.Status.Ready&&setup.Status.Missing.Length==2,"Clean first-run profile did not offer both tool groups");Capture(setup,Path.Combine(output,"windows-first-run-tools.png"));
            PressContinue();WaitIdle();check(media==1&&office==1&&setup.Status.Missing.SequenceEqual(new[]{ToolGroup.Office}),"Office failure discarded installed media or incorrectly finished setup");
            Capture(setup,Path.Combine(output,"windows-first-run-retry.png"));
            mode=1;PressContinue();check(setup.Working&&media==1,"Retry downloaded installed media again");DesktopInput.Key(setup,Key.Escape);WaitIdle();check(!setup.Status.Ready,"Cancelled setup was marked complete");
            mode=2;PressContinue();WaitIdle();check(setup.Status.Ready&&media==1&&office==3,"Retry did not finish only the missing tools");
            L10n.Language="tr";DesktopInput.Pump();check(setup.ContinueButton.Content as string=="Nashi’ye devam et","Setup footer did not update to Turkish");Capture(setup,Path.Combine(output,"windows-first-run-tools-turkish.png"));
            PressContinue();check(!setup.IsVisible&&media==1,"Continue did not finish setup without redownloading tools");
        }
        finally{setup.Close();L10n.Language=language;}
    }
    private static void Capture(Window window,string path)
    {
        window.UpdateLayout();var image=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);image.Render(window);ImageEngine.Save(image,path,"png");
    }
}
