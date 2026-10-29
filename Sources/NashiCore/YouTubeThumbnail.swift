import Foundation
import ImageIO

/// Browser drags contain a small feed preview, not necessarily the full cover.
/// Compare actual image dimensions; missing variants can return a tiny placeholder.
enum YouTubeThumbnail {
    struct Image:Sendable {
        let url:URL
        let width:Int
        let height:Int
        let byteCount:Int
        var area:Int { width*height }
    }

    static func videoID(_ url:URL)->String? {
        let host=url.host?.lowercased() ?? "",parts=url.path.split(separator:"/")
        guard ["http","https"].contains(url.scheme?.lowercased() ?? ""),url.user==nil,url.password==nil,
              url.port==nil || url.port==443 || url.port==80,
              host=="img.youtube.com" || host=="ytimg.com" || host.hasSuffix(".ytimg.com"),
              parts.count>=3,["vi","vi_webp","an_webp"].contains(parts[0]) else { return nil }
        let id=String(parts[1])
        guard id.utf8.count==11,id.utf8.allSatisfy({(65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0==45 || $0==95}) else { return nil }
        return id
    }

    static func resolve(_ source:URL,token:CancellationToken,fetch:(URL) async throws -> Data?) async throws -> Image? {
        guard let id=videoID(source) else { return nil }
        let candidates=[source]+["maxresdefault","sddefault","hqdefault"].compactMap {
            URL(string:"https://i.ytimg.com/vi/\(id)/\($0).jpg")
        }
        var seen=Set<URL>(),best:Image?
        for url in candidates where seen.insert(url).inserted {
            try token.check();try Task.checkCancellation()
            do {
                guard let data=try await fetch(url),data.count<=8*1024*1024,
                      let image=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
                      let properties=CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [CFString:Any],
                      let width=properties[kCGImagePropertyPixelWidth] as? Int,
                      let height=properties[kCGImagePropertyPixelHeight] as? Int,
                      (1...16_384).contains(width),(1...16_384).contains(height) else { continue }
                // YouTube may respond 200 with its 120×90 missing-image graphic.
                guard url==source || width>120 || height>90 else { continue }
                let found=Image(url:url,width:width,height:height,byteCount:data.count)
                if best==nil || found.area>best!.area { best=found }
            } catch {
                try token.check();try Task.checkCancellation()
                // One unavailable quality must not prevent a lower-quality cover.
            }
        }
        try token.check();try Task.checkCancellation()
        return best
    }
}
