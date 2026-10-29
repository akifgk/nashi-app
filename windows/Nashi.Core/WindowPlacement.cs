namespace Nashi.Core;

public enum WindowPlacement
{
    LeftThird, MiddleThird, RightThird, LeftHalf, RightHalf, LeftTwoThirds, RightTwoThirds, Maximize
}

public readonly record struct WindowFrame(int X,int Y,int Width,int Height)
{
    public int Right=>X+Width;
    public int Bottom=>Y+Height;
}

public static class WindowPlacements
{
    public static string Title(this WindowPlacement placement)=>placement switch
    {
        WindowPlacement.LeftThird=>"Left third", WindowPlacement.MiddleThird=>"Middle third",
        WindowPlacement.RightThird=>"Right third", WindowPlacement.LeftHalf=>"Left half",
        WindowPlacement.RightHalf=>"Right half", WindowPlacement.LeftTwoThirds=>"Left two-thirds",
        WindowPlacement.RightTwoThirds=>"Right two-thirds", WindowPlacement.Maximize=>"Maximize",
        _=>throw new ArgumentOutOfRangeException(nameof(placement))
    };
    public static (double Start,double End) Range(this WindowPlacement placement)=>placement switch
    {
        WindowPlacement.LeftThird=>(0,1d/3), WindowPlacement.MiddleThird=>(1d/3,2d/3),
        WindowPlacement.RightThird=>(2d/3,1), WindowPlacement.LeftHalf=>(0,.5),
        WindowPlacement.RightHalf=>(.5,1), WindowPlacement.LeftTwoThirds=>(0,2d/3),
        WindowPlacement.RightTwoThirds=>(1d/3,1), WindowPlacement.Maximize=>(0,1),
        _=>throw new ArgumentOutOfRangeException(nameof(placement))
    };
    public static WindowFrame Frame(this WindowPlacement placement,WindowFrame area,int minimumWidth=0)
    {
        if(area.Width<=0||area.Height<=0)return default;
        var (start,end)=placement.Range();
        var left=(int)Math.Round(area.Width*start,MidpointRounding.AwayFromZero);
        var right=(int)Math.Round(area.Width*end,MidpointRounding.AwayFromZero);
        var width=Math.Min(area.Width,Math.Max(right-left,minimumWidth));
        if(width==right-left)return new(area.X+left,area.Y,width,area.Height);
        var x=start==0?area.X:end==1?area.Right-width:area.X+(area.Width-width)/2;
        return new(x,area.Y,width,area.Height);
    }
}
