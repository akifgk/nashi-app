using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Shapes;
using Nashi.Core;
namespace Nashi.Windows;

/// Reads only the three configured modifiers and primary mouse button. It never
/// records keystrokes or polls the clipboard. Actual files/links arrive through
/// OLE drag/drop after the user chooses a wheel segment.
public sealed class GlobalDragController:IDisposable
{
    [StructLayout(LayoutKind.Sequential)]internal struct NativePoint{public int X,Y;}
    [DllImport("user32.dll")]private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")]private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")]private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]private static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
    [DllImport("user32.dll")]private static extern bool UnregisterHotKey(IntPtr window,int id);
    [StructLayout(LayoutKind.Sequential)]private struct NativeRect{public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)]private struct GuiThreadInfo{public int Size,Flags;public IntPtr Active,Focus,Capture,MenuOwner,MoveSize,Caret;public NativeRect CaretRect;}
    [DllImport("user32.dll")]private static extern bool GetGUIThreadInfo(uint thread,ref GuiThreadInfo info);
    /// True while the foreground thread is in a window move/size loop (title-bar drag).
    /// Those drags belong to window management and never carry files.
    private static bool InMoveSize(){var info=new GuiThreadInfo{Size=Marshal.SizeOf<GuiThreadInfo>()};return GetGUIThreadInfo(0,ref info)&&(info.Flags&0x2)!=0;}
    [DllImport("oleacc.dll")]private static extern int AccessibleObjectFromPoint(NativePoint point,[MarshalAs(UnmanagedType.Interface)]out object accessible,[MarshalAs(UnmanagedType.Struct)]out object child);
    private readonly Window owner;private readonly PreferencesStore preferences;private readonly Action<string,IDataObject,string?> dropped;private readonly Action link;private readonly System.Windows.Threading.DispatcherTimer timer;
    private NativePoint start;private bool down,opened;private Task<string?>? hint;private GlobalDropWheel? wheel;private HwndSource? source;private IntPtr handle;private bool? shortcutEnabled;
    internal GlobalDropWheel? ActiveWheel=>wheel;
    public bool LinkShortcutRegistered{get;private set;}
    private bool OwnerAvailable=>DesktopGeometry.IsInteractive(owner);
    public GlobalDragController(Window owner,PreferencesStore preferences,Action<string,IDataObject,string?> dropped,Action link)
    {
        this.owner=owner;this.preferences=preferences;this.dropped=dropped;this.link=link;timer=new(){Interval=TimeSpan.FromMilliseconds(40)};timer.Tick+=(_,_)=>Poll();
        if(new WindowInteropHelper(owner).Handle!=IntPtr.Zero)Register();else owner.SourceInitialized+=(_,_)=>Register();timer.Start();
    }
    private void Register(){handle=new WindowInteropHelper(owner).Handle;source=HwndSource.FromHwnd(handle);source.AddHook(Hook);UpdateShortcut();}
    private void UpdateShortcut(){if(handle==IntPtr.Zero)return;var enabled=preferences.Value.Enabled;if(shortcutEnabled==enabled)return;shortcutEnabled=enabled;if(LinkShortcutRegistered)UnregisterHotKey(handle,7701);LinkShortcutRegistered=enabled&&RegisterHotKey(handle,7701,0x4000|0x2|0x4,0x44);}
    private IntPtr Hook(IntPtr window,int message,IntPtr w,IntPtr l,ref bool handled){if(message==0x0312&&w.ToInt32()==7701){if(preferences.Value.Enabled&&OwnerAvailable)link();handled=true;}return IntPtr.Zero;}
    private static bool Held(int key)=>(GetAsyncKeyState(key)&0x8000)!=0;
    // Modifiers in the order they were pressed, so pressing Alt after Ctrl switches to the Alt function.
    private readonly List<string> pressed=[];
    private string? openedKind;private NativePoint wheelPoint;private bool blocked;private DragHintWindow? tip;private DragHintWindow? legend;private string? legendKind;private Task<bool>? draggable;
    private string? KindFor()
    {
        var current=new List<string>();if(Held(0x11))current.Add("Ctrl");if(Held(0x10))current.Add("Shift");if(Held(0x12))current.Add("Alt");
        pressed.RemoveAll(m=>!current.Contains(m));foreach(var m in current)if(!pressed.Contains(m))pressed.Add(m);
        var p=preferences.Value;var kinds=new[]{("tools",p.ToolsModifier),("convert",p.ConvertModifier),("actions",p.ActionsModifier)};
        for(var i=pressed.Count-1;i>=0;i--)
        {
            string? best=null;var size=0;
            foreach(var (kind,combo) in kinds){var set=combo.Split('+');if(set.Contains(pressed[i])&&set.All(current.Contains)&&set.Length>size){best=kind;size=set.Length;}}
            if(best is not null)return best;
        }
        return null;
    }
    private void HideTip(){tip?.Close();tip=null;}
    private void HideLegend(){legend?.Close();legend=null;legendKind=null;}
    private void ShowTip(NativePoint point)
    {
        if(!preferences.Value.DragHint||draggable is not {IsCompletedSuccessfully:true,Result:true})return;
        if(tip is null){tip=new DragHintWindow(preferences.Value);tip.Show();}
        tip.MoveTo(point.X,point.Y);
    }
    private void Poll()
    {
        UpdateShortcut();if(!preferences.Value.Enabled||!OwnerAvailable){HideTip();HideLegend();wheel?.Close();wheel=null;down=false;opened=false;openedKind=null;blocked=false;hint=null;draggable=null;return;}var held=PrimaryMouseButton.IsPressed;GetCursorPos(out var point);
        if(!held){if(down){down=false;opened=false;openedKind=null;blocked=false;hint=null;draggable=null;HideTip();HideLegend();if(wheel is {IsVisible:true}){var old=wheel;var dismiss=new System.Windows.Threading.DispatcherTimer{Interval=TimeSpan.FromMilliseconds(150)};dismiss.Tick+=(_,_)=>{dismiss.Stop();if(old.IsVisible)old.Close();};dismiss.Start();}wheel=null;}return;}
        if(!down){down=true;start=point;opened=false;openedKind=null;blocked=false;hint=null;draggable=null;pressed.Clear();return;}
        var kind=KindFor();if(Math.Abs(point.X-start.X)+Math.Abs(point.Y-start.Y)<10)return;
        hint??=Task.Run(()=>LinkAt(start));var sourceHint=hint;draggable??=Task.Run(()=>LooksDraggable(start,sourceHint));
        if(preferences.Value.DragHint&&wheel is {Revealed:true}&&openedKind is not null&&legendKind!=openedKind){HideLegend();legend=new DragHintWindow(preferences.Value,openedKind);legend.Show();legend.PlaceBelow(new WindowInteropHelper(wheel).Handle);legendKind=openedKind;}
        if(blocked)return;
        if(kind is null){if(!opened)ShowTip(point);return;}
        if(opened&&kind==openedKind)return;
        if(!opened){opened=true;if(InMoveSize()){blocked=true;HideTip();return;}wheelPoint=point;}
        // The open wheel is the current OLE drop target: change its mode in place. A new window under the pointer
        // would only receive DragEnter after the next mouse move, so it would stay invisible until then.
        else if(wheel is {IsVisible:true}){wheel.SwitchMode(kind);openedKind=kind;HideLegend();HideTip();return;}
        else{wheel?.Close();wheel=null;HideLegend();}
        HideTip();openedKind=kind;var p=preferences.Value;
        wheel=new GlobalDropWheel(kind,p.WheelScale,(data,id)=>dropped(id,data,sourceHint?.IsCompletedSuccessfully==true?sourceHint.Result:null),()=>sourceHint?.IsCompletedSuccessfully==true?sourceHint.Result:null);wheel.Show();DesktopGeometry.PlaceWheel(wheel,wheelPoint.X,wheelPoint.Y,WheelPresentation.Diameter*p.WheelScale);
    }
    /// True when the press landed on something that can carry files or a link (a file-manager item, an image, a link).
    /// Text selections, edit boxes and scrollbars never show the key hint.
    private static readonly HashSet<string> FileManagers=new(StringComparer.OrdinalIgnoreCase){"explorer","Files","7zFM","TOTALCMD64","TOTALCMD","DOpus","XYplorer","OneCommander","Q-Dir","FreeCommander","doublecmd","Nashi"};
    private static bool InFileManager(AutomationElement element)
    {
        try{using var process=System.Diagnostics.Process.GetProcessById(element.Current.ProcessId);return FileManagers.Contains(process.ProcessName);}
        catch(Exception error)when(error is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception){return false;}
    }
    private static bool LooksDraggable(NativePoint point,Task<string?> link)
    {
        try
        {
            var element=AutomationElement.FromPoint(new Point(point.X,point.Y));
            // Nashi's own windows (photo editor area selection, sliders, lists) never carry a file the wheel could take.
            if(element is not null&&element.Current.ProcessId==Environment.ProcessId)return false;
            for(var n=0;n<6&&element is not null;n++,element=TreeWalker.ControlViewWalker.GetParent(element))
            {
                var type=element.Current.ControlType;
                if(element.Current.IsPassword||type==ControlType.ScrollBar||type==ControlType.Slider||type==ControlType.TitleBar)return false;
                // Explorer puts an Edit ("UIProperty") inside every item label; keep climbing there to reach the item.
                if(type==ControlType.Edit||type==ControlType.Document){if(InFileManager(element))continue;return false;}
                // Images and links carry a URL anywhere. List/tree items carry files only in a file manager;
                // in a web page or document they are plain text rows.
                if(type==ControlType.Image||type==ControlType.Hyperlink)return true;
                if((type==ControlType.ListItem||type==ControlType.DataItem||type==ControlType.TreeItem)&&InFileManager(element))return true;
            }
        }catch(ElementNotAvailableException){}catch(InvalidOperationException){}catch(COMException){}
        try{return link.GetAwaiter().GetResult() is not null;}catch(Exception){return false;}
    }
    private static string? LinkAt(NativePoint point)
    {
        try
        {
            var element=AutomationElement.FromPoint(new Point(point.X,point.Y));for(var n=0;n<7&&element is not null;n++,element=TreeWalker.ControlViewWalker.GetParent(element))
            {
                if(element.Current.IsPassword||element.Current.ControlType==ControlType.Edit)return null;
                if(element.TryGetCurrentPattern(ValuePattern.Pattern,out var value)&&WebMediaPayload.Parse(((ValuePattern)value).Current.Value) is {} result)return result.Url;
            }
            if(AccessibleObjectFromPoint(point,out var accessible,out var child)>=0)
            {
                try{for(var n=0;n<4;n++){var value=accessible.GetType().InvokeMember("accValue",System.Reflection.BindingFlags.GetProperty,null,accessible,[child])?.ToString();if(WebMediaPayload.Parse(value) is {} link)return link.Url;var parent=accessible.GetType().InvokeMember("accParent",System.Reflection.BindingFlags.GetProperty,null,accessible,null);if(parent is null)break;Marshal.FinalReleaseComObject(accessible);accessible=parent;child=0;}}finally{if(Marshal.IsComObject(accessible))Marshal.FinalReleaseComObject(accessible);}
            }
        }catch(ElementNotAvailableException){}catch(InvalidOperationException){}catch(COMException){}catch(System.Reflection.TargetInvocationException){}catch(MissingMethodException){}return null;
    }
    public void Dispose(){timer.Stop();HideTip();HideLegend();wheel?.Close();if(handle!=IntPtr.Zero)UnregisterHotKey(handle,7701);source?.RemoveHook(Hook);}
}

internal sealed class GlobalDropWheel:Window
{
    internal string State=>$"entered={entered}, over={over}, dropped={dropCount}, choices={choices.Count}, selection={selection}, revealed={Revealed}";private int entered,over,dropCount;
    // The wheel opens almost transparent and only appears once an OLE drag carrying a file or
    // link reaches it. Plain mouse drags with a modifier (text selection, scrollbars) and OLE
    // drags of other data, such as selected text, never show it.
    // Fully transparent layered pixels ignore hit tests, so keep a tiny non-zero opacity.
    private const double HiddenOpacity=.02;
    internal bool Revealed{get;private set;}
    private void Reveal(){if(Revealed)return;Revealed=true;foreach(var label in canvas.Children.OfType<Border>())label.Visibility=Visibility.Visible;WheelPresentation.Animate(this,HiddenOpacity);if(Opacity<1&&!HasAnimatedProperties)Opacity=1;}
    private string mode;private readonly Action<IDataObject,string> chosen;private readonly Func<string?> hint;private readonly Canvas canvas=new(){Width=540,Height=540,Background=Brushes.Transparent,AllowDrop=true};private string selection="";private IReadOnlyList<ToolChoice> choices=[];
    public GlobalDropWheel(string mode,double scale,Action<IDataObject,string> chosen,Func<string?> hint)
    {
        this.mode=mode;this.chosen=chosen;this.hint=hint;Title="Nashi · "+mode;Width=Height=WheelPresentation.Diameter*scale;WindowStyle=WindowStyle.None;AllowsTransparency=true;Background=Brushes.Transparent;ResizeMode=ResizeMode.NoResize;ShowInTaskbar=false;ShowActivated=false;Topmost=true;AllowDrop=true;Content=new Viewbox{Child=canvas};Build([]);Opacity=HiddenOpacity;
        // Reveal only once the payload offers choices. On entry the pointer sits in the center,
        // so e.Effects is still None even for a valid file drag.
        DragEnter+=(_,e)=>{entered++;Track(e);if(choices.Count>0)Reveal();};
        DragOver+=(_,e)=>{over++;Track(e);if(choices.Count>0)Reveal();};
        Drop+=(_,e)=>{dropCount++;Track(e);var id=selection;Close();if(id.Length>0)chosen(e.Data,id);e.Handled=true;};PreviewKeyDown+=(_,e)=>{if(e.Key==Key.Escape){Close();e.Handled=true;}};
    }
    /// Switches Tools/Convert/File actions while a drag is over the wheel; the next DragOver rebuilds the segments.
    internal void SwitchMode(string next){if(mode==next)return;mode=next;Title="Nashi · "+next;}
    private void Track(DragEventArgs e)
    {
        var files=e.Data.GetData(DataFormats.FileDrop) as string[]??[];var updated=Choices(files,Payload(e.Data));
        // Replacing the hit-test target during DragEnter causes OLE to enter
        // again instead of advancing to DragOver. Keep the visual tree stable
        // until the payload actually changes, and select on entry as well.
        if(!updated.SequenceEqual(choices)){choices=updated;Build(choices);}
        var p=e.GetPosition(canvas);var distance=(p-new Point(270,270)).Length;
        if(distance<108||distance>250||choices.Count==0){selection="";Highlight(-1);}
        else{var angle=(Math.Atan2(p.Y-270,p.X-270)*180/Math.PI-WheelPresentation.StartAngle(choices.Count)+360+180d/choices.Count)%360;var index=(int)(angle/(360d/choices.Count));var id=choices[index].Id;if(id!=selection){selection=id;Feedback.Play();}Highlight(index);}
        e.Effects=selection.Length>0?DragDropEffects.Copy:DragDropEffects.None;e.Handled=true;
    }
    private WebMediaPayload? Payload(IDataObject data)=>DragPayload.Parse(data,hint());
    private IReadOnlyList<ToolChoice> Choices(string[] files,WebMediaPayload? web)
    {
        if(files.Length>0&&web is null)
        {
            if(mode=="convert")return FeatureCatalog.Formats(files).Select(f=>new ToolChoice("convert:"+f,f.ToUpperInvariant(),"↗")).ToArray();
            if(mode=="actions")return [new("share","Share","◉"),new("float","Float","▣"),new("copy","Copy","▱"),new("move","Move","↗"),new("copyPath","Copy Path","↪"),new("terminal","Terminal",">_")];
            return FeatureCatalog.Tools(files).Select(t=>new ToolChoice(t,FeatureCatalog.ToolNames[t],MainWindow.ToolSymbol(t))).ToArray();
        }
        if(web is null)return [];return web.Kind switch{"youtube"=>[new("download:video","Download Video","↓"),new("download:thumbnail","Download Thumbnail","▣"),new("download:audio","Download Audio","♫")],"instagramPhotos"=>[new("download:photos","Download Images","▣")],"instagramReel"=>[new("download:video","Download Video","↓"),new("download:audio","Download Audio","♫")],"image"=>[new("download:image","Download Image","↓")],_=>[new("download:video","Download Video","↓"),new("download:audio","Download Audio","♫") ]};
    }
    private TextBlock? centerText;private string centerSource="";
    private void Highlight(int index){if(centerText is not null){if(index>=0&&index<choices.Count){System.Windows.Data.BindingOperations.ClearBinding(centerText,TextBlock.TextProperty);centerText.Text=L10n.Text(choices[index].Title);}else L10n.SetText(centerText,centerSource);}var paths=canvas.Children.OfType<System.Windows.Shapes.Path>().ToArray();for(var n=0;n<paths.Length;n++){paths[n].Fill=Theme.Brush(n==index?"Sage":"Inset");paths[n].Stroke=Theme.Brush(n==index?"Gold":"Line");}}
    private void Build(IReadOnlyList<ToolChoice> tools)
    {
        canvas.Children.Clear();canvas.Children.Add(new Ellipse{Width=540,Height=540,Fill=WheelPresentation.Backdrop});var count=tools.Count;
        for(var i=0;i<count;i++)
        {
            var angle=(WheelPresentation.StartAngle(count)+360d*i/count)*Math.PI/180;var half=(180d/count-1)*Math.PI/180;Point P(double r,double a)=>new(270+r*Math.Cos(a),270+r*Math.Sin(a));var a=angle-half;var b=angle+half;var geometry=new StreamGeometry();using(var g=geometry.Open()){g.BeginFigure(P(108,a),true,true);g.LineTo(P(250,a),true,false);g.ArcTo(P(250,b),new(250,250),0,b-a>Math.PI,SweepDirection.Clockwise,true,false);g.LineTo(P(108,b),true,false);g.ArcTo(P(108,a),new(108,108),0,b-a>Math.PI,SweepDirection.Counterclockwise,true,false);}canvas.Children.Add(new System.Windows.Shapes.Path{Data=geometry,Fill=Theme.Brush("Inset"),Stroke=Theme.Brush("Line")});
            var (stack,location)=WheelPresentation.Caption(tools[i],geometry,angle,half,count);var label=new Border{Child=stack,Width=stack.DesiredSize.Width,Height=stack.DesiredSize.Height,IsHitTestVisible=false};Canvas.SetLeft(label,location.X-label.Width/2);Canvas.SetTop(label,location.Y-label.Height/2);canvas.Children.Add(label);
        }
        centerSource=count==0?"Keep dragging\nDrop a file or link":mode=="convert"?"Convert":mode=="actions"?"File actions":"Tools";centerText=new TextBlock{Text=centerSource,TextWrapping=TextWrapping.Wrap,TextAlignment=TextAlignment.Center,VerticalAlignment=VerticalAlignment.Center,FontSize=22,FontWeight=FontWeights.SemiBold,Foreground=Theme.Brush("Ink")};var center=new Border{Width=180,Height=180,IsHitTestVisible=false,Visibility=Revealed?Visibility.Visible:Visibility.Hidden,Child=L10n.Label(centerText)};Canvas.SetLeft(center,180);Canvas.SetTop(center,180);canvas.Children.Add(center);
    }
}

/// Small non-interactive key legend that follows the pointer after a drag starts. It never takes focus
/// or mouse events, so the drag underneath is unaffected.
internal sealed class DragHintWindow:Window
{
    [DllImport("user32.dll")]private static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll",EntryPoint="GetWindowLongW")]private static extern int GetWindowLong(IntPtr window,int index);
    [DllImport("user32.dll",EntryPoint="SetWindowLongW")]private static extern int SetWindowLong(IntPtr window,int index,int value);
    public DragHintWindow(Preferences preferences,string? current=null)
    {
        WindowStyle=WindowStyle.None;AllowsTransparency=true;Background=Brushes.Transparent;ShowInTaskbar=false;ShowActivated=false;Topmost=true;ResizeMode=ResizeMode.NoResize;SizeToContent=SizeToContent.WidthAndHeight;Focusable=false;IsHitTestVisible=false;Title="Nashi · hint";
        var stack=new StackPanel{Orientation=current is null?Orientation.Vertical:Orientation.Horizontal};
        void Row(string keys,string title)
        {
            var chip=new Border{Background=Theme.Brush("Inset"),BorderBrush=Theme.Brush("Line"),BorderThickness=new(1),CornerRadius=new(5),Padding=new(7,1,7,2),Margin=new(0,0,10,0),MinWidth=54,Child=new TextBlock{Text=keys,FontSize=12,FontWeight=FontWeights.SemiBold,Foreground=Theme.Brush("Ink"),HorizontalAlignment=HorizontalAlignment.Center}};
            var row=new StackPanel{Orientation=Orientation.Horizontal,Margin=current is null?new(0,2,0,2):new(8,0,8,0)};row.Children.Add(chip);row.Children.Add(L10n.Label(new TextBlock{Text=title,FontSize=13,Foreground=Theme.Brush("Ink"),VerticalAlignment=VerticalAlignment.Center}));stack.Children.Add(row);
        }
        if(current!="tools")Row(preferences.ToolsModifier,"Tools");if(current!="convert")Row(preferences.ConvertModifier,"Convert");if(current!="actions")Row(preferences.ActionsModifier,"File actions");
        Content=new Border{Background=Theme.Brush("Surface"),BorderBrush=Theme.Brush("Line"),BorderThickness=new(1),CornerRadius=new(current is null?10:16),Padding=current is null?new(10,6,12,6):new(8,6,8,6),Child=stack,Opacity=.96};
        // WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE: pointer events pass through, no focus, no taskbar entry.
        SourceInitialized+=(_,_)=>{var handle=new WindowInteropHelper(this).Handle;SetWindowLong(handle,-20,GetWindowLong(handle,-20)|0x20|0x80|0x08000000);};
    }
    [StructLayout(LayoutKind.Sequential)]private struct Rect{public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)]private struct MonitorInfo{public int Size;public Rect Monitor,Work;public uint Flags;}
    [DllImport("user32.dll")]private static extern bool GetWindowRect(IntPtr window,out Rect rect);
    [DllImport("user32.dll")]private static extern IntPtr MonitorFromWindow(IntPtr window,uint flags);
    [DllImport("user32.dll")]private static extern bool GetMonitorInfo(IntPtr monitor,ref MonitorInfo info);
    /// Centers the legend under the wheel; flips above it when the wheel sits at the bottom of the screen.
    internal void PlaceBelow(IntPtr wheelHandle)
    {
        var handle=new WindowInteropHelper(this).Handle;if(handle==IntPtr.Zero||!GetWindowRect(wheelHandle,out var wheel)||!GetWindowRect(handle,out var own))return;
        var width=own.Right-own.Left;var height=own.Bottom-own.Top;var gap=8;var x=(wheel.Left+wheel.Right-width)/2;var y=wheel.Bottom+gap;
        var info=new MonitorInfo{Size=Marshal.SizeOf<MonitorInfo>()};
        if(GetMonitorInfo(MonitorFromWindow(wheelHandle,2),ref info)){x=Math.Clamp(x,info.Work.Left,Math.Max(info.Work.Left,info.Work.Right-width));if(y+height>info.Work.Bottom)y=wheel.Top-height-gap;}
        SetWindowPos(handle,new IntPtr(-1),x,y,0,0,0x11);
    }
    internal void MoveTo(int x,int y){var handle=new WindowInteropHelper(this).Handle;if(handle!=IntPtr.Zero)SetWindowPos(handle,new IntPtr(-1),x+22,y+26,0,0,0x11);}
}
