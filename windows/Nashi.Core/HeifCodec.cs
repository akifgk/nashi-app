using System.Buffers.Binary;
using System.Text;
namespace Nashi.Core;

/// Packages a single independently encoded HEVC still into an ISO BMFF HEIF
/// item. The HEVC configuration and sample are taken from FFmpeg's real MP4,
/// so the file is HEIC rather than another codec with a changed extension.
public static class HeifCodec
{
    private static byte[] Text(string value)=>Encoding.ASCII.GetBytes(value);
    private static byte[] U32(uint n){var b=new byte[4];BinaryPrimitives.WriteUInt32BigEndian(b,n);return b;}
    private static byte[] U16(ushort n){var b=new byte[2];BinaryPrimitives.WriteUInt16BigEndian(b,n);return b;}
    private static byte[] Join(params byte[][] parts)=>parts.SelectMany(p=>p).ToArray();
    private static byte[] Box(string type,params byte[][] parts){var payload=Join(parts);return Join(U32(checked((uint)payload.Length+8)),Text(type),payload);}
    private sealed record Part(string Type,int Start,int Header,int Size);
    private static IEnumerable<Part> Parts(byte[] source,int start,int end)
    {
        while(start<=end-8){var size=BinaryPrimitives.ReadUInt32BigEndian(source.AsSpan(start,4));var header=8;long length=size;if(size==1){if(start>end-16)throw new InvalidDataException("Invalid video box.");length=checked((long)BinaryPrimitives.ReadUInt64BigEndian(source.AsSpan(start+8,8)));header=16;}else if(size==0)length=end-start;if(length<header||length>end-start)throw new InvalidDataException("Invalid video box size.");yield return new(Encoding.ASCII.GetString(source,start+4,4),start,header,(int)length);start+=(int)length;}
    }
    private static Part Find(byte[] data,string[] route)
    {
        var start=0;var end=data.Length;Part? result=null;foreach(var name in route){result=Parts(data,start,end).Single(p=>p.Type==name);start=result.Start+result.Header+(name=="stsd"?8:name is "hvc1" or "hev1"?78:0);end=result.Start+result.Size;}return result!;
    }
    public static async Task EncodeAsync(string encoder,byte[] png,string output,int width,int height,int quality,CancellationToken token=default)
    {
        if(width<1||height<1)throw new ArgumentException("Choose a nonempty image.");var work=Path.Combine(Path.GetDirectoryName(output)!,".heif-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(work);
        try
        {
            var input=Path.Combine(work,"source.png");var video=Path.Combine(work,"still.mp4");await File.WriteAllBytesAsync(input,png,token);
            await ProcessRunner.RunAsync(encoder,["-hide_banner","-nostdin","-v","error","-i",input,"-frames:v","1","-an","-vf","pad=ceil(iw/2)*2:ceil(ih/2)*2","-c:v","libx265","-profile:v","mainstillpicture","-preset","medium","-crf",Math.Clamp(40-quality*.3,8,40).ToString(System.Globalization.CultureInfo.InvariantCulture),"-pix_fmt","yuv420p","-tag:v","hvc1","-x265-params","log-level=error:pools=1:frame-threads=1","-color_primaries","bt709","-color_trc","iec61966-2-1","-colorspace","bt709","-color_range","pc",video],token);
            var bytes=await File.ReadAllBytesAsync(video,token);var configuration=Find(bytes,["moov","trak","mdia","minf","stbl","stsd","hvc1","hvcC"]);var config=bytes.AsSpan(configuration.Start,configuration.Size).ToArray();var mdat=Find(bytes,["mdat"]);var sample=bytes.AsSpan(mdat.Start+mdat.Header,mdat.Size-mdat.Header).ToArray();
            var paddedWidth=(uint)((width+1)/2*2);var paddedHeight=(uint)((height+1)/2*2);var cropped=paddedWidth!=width||paddedHeight!=height;
            var ftyp=Box("ftyp",Text("heic"),U32(0),Text("mif1heicmiaf"));
            byte[] Metadata(uint offset)
            {
                var properties=new List<byte[]>{config,Box("ispe",U32(0),U32(paddedWidth),U32(paddedHeight)),Box("pixi",U32(0),[3,8,8,8]),Box("colr",Text("nclx"),U16(1),U16(13),U16(1),[0x80])};
                if(cropped)properties.Add(Box("clap",U32((uint)width),U32(1),U32((uint)height),U32(1),U32(unchecked((uint)(width-(int)paddedWidth))),U32(2),U32(unchecked((uint)(height-(int)paddedHeight))),U32(2)));
                return Box("meta",U32(0),Box("hdlr",U32(0),U32(0),Text("pict"),new byte[12],Text("Nashi\0")),Box("pitm",U32(0),U16(1)),Box("iloc",U32(0),[0x44,0],U16(1),U16(1),U16(0),U16(1),U32(offset),U32((uint)sample.Length)),Box("iinf",U32(0),U16(1),Box("infe",U32(0x02000000),U16(1),U16(0),Text("hvc1"),Text("Image\0"))),Box("iprp",Box("ipco",properties.ToArray()),Box("ipma",U32(0),U32(1),U16(1),[(byte)properties.Count],Enumerable.Range(1,properties.Count).Select(i=>(byte)(0x80|i)).ToArray())));
            }
            var meta=Metadata(0);meta=Metadata((uint)(ftyp.Length+meta.Length+8));await File.WriteAllBytesAsync(output,Join(ftyp,meta,Box("mdat",sample)),token);
        }finally{if(Directory.Exists(work))Directory.Delete(work,true);}
    }
}
