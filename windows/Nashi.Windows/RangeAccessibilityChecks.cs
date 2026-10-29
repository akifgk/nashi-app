using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace Nashi.Windows;

/// Uses the production control and UIA providers inside an isolated fixture
/// window. No SendInput, clipboard, user Library or system permissions are used.
internal static class RangeAccessibilityChecks
{
    internal static void Run(string output,Window owner,Action<bool,string> check)
    {
        Directory.CreateDirectory(output);
        var checks=new List<string>();string? failure=null;var language=L10n.Language;var changes=0;
        var timeline=new RangeTimeline{Width=400};timeline.Set(10,2,8);
        timeline.Changed+=(_,_)=>changes++;
        var panel=new StackPanel{Margin=new Thickness(24)};
        panel.Children.Add(new TextBlock{Text="Trim · semantic Start and End",Margin=new Thickness(0,0,0,20),FontSize=18});
        panel.Children.Add(timeline);panel.Children.Add(new TextBlock{Text="2.000 – 8.000 seconds",Margin=new Thickness(0,20,0,0)});
        var window=new Window{Owner=owner,Title="Nashi Range Accessibility QA",SizeToContent=SizeToContent.WidthAndHeight,ResizeMode=ResizeMode.NoResize,Content=panel};
        void Assert(bool valid,string label){check(valid,label);checks.Add(label);}
        bool Near(double a,double b)=>Math.Abs(a-b)<.000001;
        bool Rejects(double value,IRangeValueProvider provider)
        {
            try{provider.SetValue(value);return false;}catch(ArgumentOutOfRangeException){return true;}
        }
        try
        {
            L10n.Language="en";window.Show();window.UpdateLayout();DesktopInput.Pump();
            var peer=UIElementAutomationPeer.CreatePeerForElement(timeline)!;
            var children=peer.GetChildren();
            Assert(peer.GetAutomationId()=="media.range.timeline"&&peer.GetAutomationControlType()==AutomationControlType.Group,"Timeline exposes a stable semantic group");
            Assert(children is {Count:2},"One selected range exposes independent start and end controls");
            var startPeer=children![0];var endPeer=children[1];
            Assert(startPeer.GetAutomationId()=="media.range.0.start"&&endPeer.GetAutomationId()=="media.range.0.end","Start and end controls have stable UIA identifiers");
            Assert(startPeer.GetAutomationControlType()==AutomationControlType.Slider&&endPeer.GetAutomationControlType()==AutomationControlType.Slider,"Both endpoints expose native slider roles");
            Assert(startPeer.GetName()==L10n.Text("Start")&&endPeer.GetName()==L10n.Text("End"),"Endpoint names follow the app language");
            var start=(IRangeValueProvider)startPeer.GetPattern(PatternInterface.RangeValue)!;
            var end=(IRangeValueProvider)endPeer.GetPattern(PatternInterface.RangeValue)!;
            Assert(!start.IsReadOnly&&!end.IsReadOnly&&Near(start.SmallChange,.1)&&Near(end.LargeChange,1),"Both endpoints publish editable RangeValue providers and useful time steps");
            Assert(Near(start.Value,2)&&Near(end.Value,8)&&Near(start.Minimum,0)&&Near(start.Maximum,7.95),"Start publishes source and opposite-edge bounds in seconds");
            Assert(Near(end.Minimum,2.05)&&Near(end.Maximum,10),"End publishes source and opposite-edge bounds in seconds");
            Assert(!startPeer.GetBoundingRectangle().IsEmpty&&!endPeer.GetBoundingRectangle().IsEmpty,"Both UIA endpoint frames identify the painted handles");
            start.SetValue(start.Value+start.SmallChange);
            Assert(Near(timeline.Start,2.1)&&Near(timeline.End,8)&&changes==1,"A provider increment changes only Start through the production callback");
            end.SetValue(end.Value-end.SmallChange);
            Assert(Near(timeline.Start,2.1)&&Near(timeline.End,7.9)&&changes==2,"A provider decrement changes only End through the production callback");
            Assert(ReferenceEquals(peer.GetChildren()[0],startPeer)&&ReferenceEquals(peer.GetChildren()[1],endPeer),"Value updates preserve child peer identity");
            var beforeInvalid=changes;
            Assert(Rejects(9,start)&&Rejects(-1,end)&&Rejects(-100,start)&&Rejects(100,end),"UIA rejects crossing or out-of-source SetValue requests without changing either edge");
            Assert(Rejects(double.NaN,start)&&Rejects(double.PositiveInfinity,end)&&changes==beforeInvalid,"UIA rejects non-finite values without invoking the callback");
            start.SetValue(start.Maximum);
            Assert(Near(timeline.Start,7.85)&&Near(timeline.End,7.9),"The exact Start maximum preserves the minimum span");
            start.SetValue(start.Minimum);end.SetValue(end.Minimum);
            Assert(Near(timeline.Start,0)&&Near(timeline.End,.05),"The exact minimum endpoints preserve a valid selected range");
            end.SetValue(end.Maximum);var boundaryCount=changes;end.SetValue(end.Maximum);
            Assert(Near(timeline.End,10)&&changes==boundaryCount,"Setting an unchanged boundary does not duplicate the production callback");
            timeline.IsEnabled=false;
            var disabledRejected=false;
            try{start.SetValue(1);}catch(ElementNotEnabledException){disabledRejected=true;}
            Assert(start.IsReadOnly&&end.IsReadOnly&&!startPeer.IsEnabled()&&disabledRejected&&changes==boundaryCount,"Disabled timelines advertise read-only endpoints and reject semantic edits");
            timeline.IsEnabled=true;timeline.Set(20,4,16);
            Assert(Near(start.Value,4)&&Near(end.Value,16)&&Near(start.Maximum,15.95)&&Near(end.Minimum,4.05)&&Near(end.Maximum,20),"External range changes update the existing UIA values and independent bounds");
            timeline.Set(.01,0,.01);
            Assert(Near(start.Minimum,0)&&Near(start.Maximum,0)&&Near(end.Minimum,.05)&&Near(end.Maximum,.05),"Very short sources keep ordered endpoint bounds under the existing timeline minimum");
            timeline.Set(double.NaN,double.NaN,double.NaN);
            Assert(double.IsFinite(start.Value)&&double.IsFinite(end.Value)&&start.Minimum<=start.Maximum&&end.Minimum<=end.Maximum,"Unavailable source values cannot publish non-finite or inverted UIA bounds");
            L10n.Language="tr";
            Assert(startPeer.GetName()==L10n.Text("Start")&&endPeer.GetName()==L10n.Text("End")&&startPeer.GetHelpText()==L10n.Text("Seconds"),"Endpoint names and units use Turkish localization");
            timeline.Set(10,2,8);window.UpdateLayout();
            var image=new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth),(int)Math.Ceiling(window.ActualHeight),96,96,PixelFormats.Pbgra32);image.Render(window);
            ImageEngine.Save(image,Path.Combine(output,"windows-range-accessibility.png"),"png");
        }
        catch(Exception error){failure=error.Message;throw;}
        finally
        {
            File.WriteAllText(Path.Combine(output,"windows-range-accessibility.json"),JsonSerializer.Serialize(new{passed=failure is null,checks,error=failure,scope="Own-window production control and UIA RangeValue providers. No global input, clipboard, Library or external screen-reader client."},new JsonSerializerOptions{WriteIndented=true}));
            window.Close();L10n.Language=language;
        }
    }
}
