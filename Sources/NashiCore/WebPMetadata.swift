import Foundation

/// Rewrites metadata chunks while retaining the original encoded image/animation bytes.
/// Layout follows https://developers.google.com/speed/webp/docs/riff_container.
enum WebPMetadataContainer {
    struct Chunk { var name:String; var payload:Data }

    static func chunks(_ data:Data) throws -> [Chunk] {
        let bytes=[UInt8](data)
        guard bytes.count>=12,String(bytes:bytes[0..<4],encoding:.ascii)=="RIFF",String(bytes:bytes[8..<12],encoding:.ascii)=="WEBP" else { throw NashiError.invalidInput("This is not a WebP container.") }
        let end=Int(read32(bytes,4))+8
        guard end<=bytes.count,end>=12 else { throw NashiError.invalidInput("The WebP container is truncated.") }
        var result:[Chunk]=[],offset=12
        while offset<end {
            guard offset+8<=end else { throw NashiError.invalidInput("The WebP chunk header is incomplete.") }
            let length=Int(read32(bytes,offset+4)),start=offset+8
            guard length<=end-start,start+length+(length%2)<=end,let name=String(bytes:bytes[offset..<offset+4],encoding:.ascii) else { throw NashiError.invalidInput("The WebP chunk is invalid.") }
            result.append(Chunk(name:name,payload:Data(bytes[start..<start+length])))
            offset=start+length+(length%2)
        }
        return result
    }

    static func replaceEXIF(_ data:Data,exif:Data?,removeXMP:Bool,width:Int,height:Int) throws -> Data {
        guard width>0,height>0,width<=0x1000000,height<=0x1000000 else { throw NashiError.invalidInput("Invalid WebP canvas dimensions.") }
        var items=try chunks(data).filter { $0.name != "EXIF" && !(removeXMP && $0.name == "XMP ") }
        if let exif,!exif.isEmpty { items.append(Chunk(name:"EXIF",payload:exif)) }
        let existing=items.firstIndex { $0.name=="VP8X" }
        let hasExtended=existing != nil || exif != nil
        if hasExtended {
            var flags:UInt8=0
            if items.contains(where:{$0.name=="ICCP"}) { flags |= 0x20 }
            if items.contains(where:{$0.name=="ALPH" || ($0.name=="VP8L" && $0.payload.count>=5 && ($0.payload[$0.payload.startIndex+4]&0x10) != 0)}) { flags |= 0x10 }
            if let existing,items[existing].payload.count==10 { flags |= items[existing].payload[items[existing].payload.startIndex]&0x10 }
            if items.contains(where:{$0.name=="EXIF"}) { flags |= 0x08 }
            if items.contains(where:{$0.name=="XMP "}) { flags |= 0x04 }
            if items.contains(where:{$0.name=="ANIM" || $0.name=="ANMF"}) { flags |= 0x02 }
            var extended=Data([flags,0,0,0]);append24(width-1,to:&extended);append24(height-1,to:&extended)
            if let existing { items[existing].payload=extended }
            else { items.insert(Chunk(name:"VP8X",payload:extended),at:0) }
        }
        var body=Data("WEBP".utf8)
        for item in items {
            guard item.payload.count<=Int(UInt32.max) else { throw NashiError.invalidInput("WebP metadata is too large.") }
            body.append(Data(item.name.utf8));append32(UInt32(item.payload.count),to:&body);body.append(item.payload)
            if item.payload.count%2 != 0 { body.append(0) }
        }
        guard body.count<=Int(UInt32.max)-9 else { throw NashiError.invalidInput("The WebP file is too large.") }
        var output=Data("RIFF".utf8);append32(UInt32(body.count),to:&output);output.append(body);return output
    }

    static func exifPayload(fromJPEG data:Data) throws -> Data {
        let bytes=[UInt8](data)
        guard bytes.count>=4,bytes[0]==0xFF,bytes[1]==0xD8 else { throw NashiError.failed("Could not encode Exif metadata.") }
        var offset=2
        while offset+4<=bytes.count {
            guard bytes[offset]==0xFF else { break }
            let marker=bytes[offset+1]
            if marker==0xDA || marker==0xD9 { break }
            let length=Int(bytes[offset+2])*256+Int(bytes[offset+3]),start=offset+4,end=offset+2+length
            guard length>=2,end<=bytes.count else { break }
            if marker==0xE1,end-start>=6,Array(bytes[start..<start+6])==[69,120,105,102,0,0] { return Data(bytes[start..<end]) }
            offset=end
        }
        throw NashiError.failed("The local encoder could not serialize these Exif tags.")
    }

    /// ImageIO omits some IFD0 text fields when the file lacks an orientation tag.
    static func tiffTextFields(_ exif:Data)->[String:String] {
        var bytes=[UInt8](exif)
        if bytes.starts(with:[69,120,105,102,0,0]) { bytes=Array(bytes.dropFirst(6)) }
        guard bytes.count>=8 else { return [:] }
        let little=bytes[0]==73 && bytes[1]==73
        guard little || bytes[0]==77 && bytes[1]==77 else { return [:] }
        func number(_ offset:Int,_ size:Int)->Int? {
            guard offset>=0,size>0,offset<=bytes.count-size else { return nil }
            var result=0
            for index in 0..<size { result |= Int(bytes[offset+index]) << ((little ? index : size-1-index)*8) }
            return result
        }
        guard number(2,2)==42,let start=number(4,4),let count=number(start,2),start+2<=bytes.count,count<=(bytes.count-start-2)/12 else { return [:] }
        let names=[269:"DocumentName",270:"ImageDescription",271:"Make",272:"Model",305:"Software",306:"DateTime",315:"Artist",316:"HostComputer",33432:"Copyright"]
        var result:[String:String]=[:]
        for index in 0..<count {
            let entry=start+2+index*12
            guard let tag=number(entry,2),let name=names[tag],number(entry+2,2)==2,let length=number(entry+4,4),length>0,let location=length<=4 ? entry+8 : number(entry+8,4),location<=bytes.count-length else { continue }
            let value=Data(bytes[location..<location+length].prefix(while:{$0 != 0}))
            result[name]=String(data:value,encoding:.utf8) ?? String(data:value,encoding:.isoLatin1)
        }
        return result
    }

    private static func read32(_ bytes:[UInt8],_ offset:Int)->UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset+1])<<8 | UInt32(bytes[offset+2])<<16 | UInt32(bytes[offset+3])<<24
    }
    private static func append32(_ value:UInt32,to data:inout Data) { data.append(contentsOf:[UInt8(value&255),UInt8((value>>8)&255),UInt8((value>>16)&255),UInt8((value>>24)&255)]) }
    private static func append24(_ value:Int,to data:inout Data) { data.append(contentsOf:[UInt8(value&255),UInt8((value>>8)&255),UInt8((value>>16)&255)]) }
}
