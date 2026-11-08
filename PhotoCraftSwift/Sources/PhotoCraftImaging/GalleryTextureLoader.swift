import CoreGraphics
import Foundation
import ImageIO
import PhotoCraftCore

public enum GalleryTextureLoader {
  public static let maximumInputBytes = 64 * 1024 * 1024
  public static func read(_ url:URL) throws -> GalleryTextureSource {
    guard url.isFileURL else {throw CraftError.invalid("Choose a local Photoshop texture file.")}
    let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
    let data=try handle.read(upToCount:maximumInputBytes+1) ?? Data()
    try Task.checkCancellation()
    return try decode(data,name:url.lastPathComponent)
  }
  public static func decode(_ data:Data,name:String) throws -> GalleryTextureSource {
    try Task.checkCancellation()
    let data=Data(data)
    guard data.count>=40,data.count<=maximumInputBytes,data.starts(with:Data("8BPS".utf8)) else {throw CraftError.invalid("Choose a Photoshop PSD/PSB texture, up to 64 MiB.")}
    func word(_ p:Int)->Int {Int(data[p])*256+Int(data[p+1])}
    func integer(_ p:Int)->Int {(0..<4).reduce(0){($0<<8)|Int(data[p+$1])}}
    let w=integer(18),h=integer(14)
    guard [1,2].contains(word(4)),(1...300_000).contains(w),(1...300_000).contains(h),w<=GalleryTextureSource.maximumPixels/h else {throw CraftError.invalid("Texture dimensions exceed the current 8 MP limit.")}
    guard let source=CGImageSourceCreateWithData(data as CFData,nil),let image=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCache:false] as CFDictionary),image.width==w,image.height==h else {throw CraftError.invalid("The Photoshop texture has no supported merged image.")}
    let surface=try RasterIO.surface(image,depth:.u8)
    var samples=Data(count:w*h)
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let p=surface.pixel(x:x,y:y)
      samples[y*w+x]=UInt8((min(1,max(0,0.299*p.r+0.587*p.g+0.114*p.b))*255).rounded())
    }}
    return try GalleryTextureSource(name:name,width:w,height:h,samples:samples)
  }
}
