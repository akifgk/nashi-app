using System.Diagnostics;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
namespace Nashi.Windows;

/// Opt-in STA smoke helper: isolated fixture paths and injected slow shell calls, no user Library.
internal static class FileArtworkSmoke
{
    internal static void Run(string root,Action<bool,string> check)
    {
        var dispatcher=Dispatcher.CurrentDispatcher;var gate=new object();var loads=0;var version=1L;var exists=true;var uiWork=false;var lags=new List<double>();
        ImageSource Slow(string path,FileArtworkStamp stamp)
        {
            var start=Stopwatch.GetTimestamp();lock(gate){loads++;uiWork|=dispatcher.CheckAccess();}
            dispatcher.BeginInvoke(new Action(()=>{lock(gate)lags.Add(Stopwatch.GetElapsedTime(start).TotalMilliseconds);}));
            Thread.Sleep(80);var image=BitmapSource.Create(1,1,96,96,PixelFormats.Bgra32,null,new byte[]{0,0,0,255},4);image.Freeze();return image;
        }
        var fixture=Path.Combine(root,"file-artwork-fixture.pdf");
        for(var index=0;index<8;index++)Slow(fixture,default);
        Drain(dispatcher);double baselineLag;lock(gate){baselineLag=lags.Max();loads=0;uiWork=false;lags.Clear();}
        var cache=new FileArtworkCache((path,stamp)=>Task.Run<ImageSource?>(()=>Slow(path,stamp)),capacity:2,stamp:_=>{lock(gate){uiWork|=dispatcher.CheckAccess();return new(exists,false,version,version);}});
        Pump(Task.WhenAll(Enumerable.Range(0,8).Select(_=>cache.GetAsync(fixture))),dispatcher);Drain(dispatcher);
        int asyncLoads;double asyncLag;lock(gate){asyncLoads=loads;asyncLag=lags.Max();}
        check(asyncLoads==1,"Artwork: eight simultaneous rows share one shell load");
        check(!uiWork,"Artwork: shell and metadata providers run off the UI queue");
        check(asyncLag<baselineLag/2,"Artwork: UI queue remains responsive while the injected provider is slow");
        for(var index=0;index<8;index++)Pump(cache.GetAsync(fixture),dispatcher);
        check(loads==1,"Artwork: warm requests reuse their cached icon");
        version++;Pump(cache.GetAsync(fixture),dispatcher);check(loads==2,"Artwork: changed files refresh their icon");
        exists=false;Pump(cache.GetAsync(fixture),dispatcher);check(loads==3,"Artwork: missing files refresh their semantic icon");
        exists=true;Pump(cache.GetAsync(fixture),dispatcher);check(loads==4,"Artwork: recreated files replace missing-file artwork");
        Pump(cache.GetAsync(Path.Combine(root,"b.png")),dispatcher);Pump(cache.GetAsync(Path.Combine(root,"c.txt")),dispatcher);
        check(cache.CachedCount==2,"Artwork: cache respects its configured entry limit");
        Pump(cache.GetAsync(fixture),dispatcher);check(loads==7,"Artwork: least-recently-used entries are evicted and reloadable");
        Directory.CreateDirectory(root);File.WriteAllText(fixture,"fixture");var initial=FileArtworkStamp.Read(fixture);File.WriteAllText(fixture,"changed fixture length");
        check(initial.Exists&&FileArtworkStamp.Read(fixture)!=initial,"Artwork: real metadata detects a replaced file");
        var imageControl=new Image();var watch=Stopwatch.StartNew();FileArtwork.Bind(imageControl,fixture);WaitReady(imageControl,dispatcher);
        var nativeCold=watch.Elapsed.TotalMilliseconds;
        check(imageControl.Source is BitmapSource{IsFrozen:true},"Artwork: actual shell icon is immutable and reaches the dispatcher");
        FileArtwork.Bind(imageControl,Path.Combine(root,"missing-file.png"));WaitReady(imageControl,dispatcher);
        check(imageControl.Source is BitmapSource{IsFrozen:true},"Artwork: a missing file still has a semantic extension icon");
        var failed=new Image();FileArtwork.BindForTest(failed,fixture,new FileArtworkCache((_,_)=>Task.FromResult<ImageSource?>(null)));WaitReady(failed,dispatcher);
        check(FileArtwork.GetIsReady(failed)&&!FileArtwork.GetIsLoading(failed)&&failed.Source is not null,"Artwork: a failed provider reaches a terminal ready state with a placeholder");
        // Force the earlier path to complete last, rather than rely on shell timing or fixed sleeps.
        var oldImage=BitmapSource.Create(1,1,96,96,PixelFormats.Bgra32,null,new byte[]{0,0,255,255},4);oldImage.Freeze();
        var latestImage=BitmapSource.Create(1,1,96,96,PixelFormats.Bgra32,null,new byte[]{0,255,0,255},4);latestImage.Freeze();
        var previous=new TaskCompletionSource<ImageSource?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var isolated=new FileArtworkCache((path,_)=>path.EndsWith("latest.txt",StringComparison.Ordinal)?Task.FromResult<ImageSource?>(latestImage):previous.Task);
        var recycled=new Image();FileArtwork.BindForTest(recycled,fixture,isolated);FileArtwork.Bind(recycled,Path.Combine(root,"latest.txt"));WaitReady(recycled,dispatcher);
        previous.SetResult(oldImage);Pump(isolated.GetAsync(fixture),dispatcher);Drain(dispatcher);
        check(ReferenceEquals(recycled.Source,latestImage)&&FileArtwork.GetIsReady(recycled),"Artwork: a delayed previous path cannot overwrite a recycled control or readiness");
        File.WriteAllText(Path.Combine(root,"file-artwork.json"),JsonSerializer.Serialize(new{baselineProviderCalls=8,asyncProviderCalls=asyncLoads,baselineUIQueueDelayMs=baselineLag,asyncUIQueueDelayMs=asyncLag,nativeColdMs=nativeCold,scope="Injected slow provider and real Windows shell icon, isolated fixture files."},new JsonSerializerOptions{WriteIndented=true}));
    }
    private static void WaitReady(Image image,Dispatcher dispatcher)
    {
        if(FileArtwork.GetIsReady(image))return;
        var completion=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var started=Stopwatch.GetTimestamp();
        var timer=new DispatcherTimer(DispatcherPriority.Background,dispatcher){Interval=TimeSpan.FromMilliseconds(10)};
        EventHandler tick=(_,_)=>
        {
            if(FileArtwork.GetIsReady(image))completion.TrySetResult();
            else if(Stopwatch.GetElapsedTime(started)>=TimeSpan.FromSeconds(10))completion.TrySetException(new TimeoutException("File artwork did not reach its terminal readiness state within 10 seconds."));
        };
        timer.Tick+=tick;
        try{timer.Start();tick(null,EventArgs.Empty);Pump(completion.Task,dispatcher);}
        finally{timer.Stop();timer.Tick-=tick;}
    }
    private static void Drain(Dispatcher dispatcher)
    {var frame=new DispatcherFrame();dispatcher.BeginInvoke(DispatcherPriority.Background,new Action(()=>frame.Continue=false));Dispatcher.PushFrame(frame);}
    private static void Pump(Task task,Dispatcher dispatcher)
    {
        if(!task.IsCompleted)
        {
            var frame=new DispatcherFrame();_ = task.ContinueWith(_=>dispatcher.BeginInvoke(new Action(()=>frame.Continue=false)),TaskScheduler.Default);Dispatcher.PushFrame(frame);
        }
        task.GetAwaiter().GetResult();
    }
}
