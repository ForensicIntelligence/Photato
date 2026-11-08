import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import PhotoCraftCore
import zlib

/// Single-part scan-line HDR interchange. File layout and ZIP byte prediction
/// follow ASWF's public specification; no bundled C/C++ OpenEXR runtime.
public enum OpenEXR {
  public enum Compression:String,Codable,CaseIterable,Sendable {case none,zips,zip
    var code:Int{switch self{case .none:0;case .zips:2;case .zip:3}}
    var lines:Int{self == .zip ? 16:1}
  }
  public enum Sample:String,Codable,CaseIterable,Sendable {case half,float
    var bytes:Int{self == .half ? 2:4}
    var code:Int{self == .half ? 1:2}
  }
  public static let contentType=UTType("com.ilm.openexr-image") ?? UTType(importedAs:"com.ilm.openexr-image",conformingTo:.image)
  public static let mediaType="image/x-exr"
  public static let maximumBytes=512*1024*1024
  static let maximumBlockBytes=128*1024*1024
  static let magic=Data([0x76,0x2f,0x31,0x01])
  public static func recognizes(_ data:Data)->Bool {data.starts(with:magic)}
  static let primaries:[Float]=[0.64,0.33,0.30,0.60,0.15,0.06,0.3127,0.3290]
  struct Writer {
    var data=Data()
    mutating func u(_ value:UInt64,_ size:Int){for i in 0..<size{data.append(UInt8(truncatingIfNeeded:value>>UInt64(i*8)))}}
    mutating func i(_ value:Int,_ size:Int=4){u(UInt64(bitPattern:Int64(value)),size)}
    mutating func f(_ value:Float){u(UInt64(value.bitPattern),4)}
    mutating func text(_ value:String){data.append(contentsOf:value.utf8);data.append(0)}
    mutating func attr(_ name:String,_ type:String,_ value:Data){text(name);text(type);i(value.count);data.append(value)}
  }
  struct Reader {
    let data:Data;var offset:Int=0
    var remaining:Int{data.count-offset}
    mutating func bytes(_ count:Int)throws->Data{guard count>=0,count<=remaining else{throw CraftError.invalid("Truncated OpenEXR data.")};defer{offset+=count};return data.subdata(in:offset..<offset+count)}
    mutating func u(_ size:Int=4)throws->UInt64{let b=try bytes(size);return b.enumerated().reduce(0){$0|UInt64($1.element)<<UInt64($1.offset*8)}}
    mutating func i()throws->Int{Int(Int32(bitPattern:UInt32(try u())))}
    mutating func f()throws->Float{Float(bitPattern:UInt32(try u()))}
    mutating func text()throws->String {
      let start=offset;while remaining>0,offset-start<=255{let value=data[offset];offset+=1;if value==0{guard let text=String(data:data.subdata(in:start..<offset-1),encoding:.utf8)else{throw CraftError.invalid("Invalid OpenEXR attribute name.")};return text}}
      throw CraftError.invalid("OpenEXR attribute name is too long or truncated.")
    }
  }
  static func pack(_ raw:[UInt8])throws->Data {
    var shuffled=[UInt8](repeating:0,count:raw.count);let half=(raw.count+1)/2
    for i in raw.indices{shuffled[i/2+(i%2==0 ? 0:half)]=raw[i]}
    if shuffled.count>1{var previous=shuffled[0];for i in 1..<shuffled.count{let next=shuffled[i];shuffled[i]=next &- previous &+ 128;previous=next}}
    var count=compressBound(uLong(shuffled.count)),compressed=[UInt8](repeating:0,count:Int(count))
    let status=compressed.withUnsafeMutableBufferPointer{out in shuffled.withUnsafeBufferPointer{input in compress2(out.baseAddress!,&count,input.baseAddress!,uLong(input.count),Z_DEFAULT_COMPRESSION)}}
    guard status==Z_OK else{throw CraftError.invalid("OpenEXR ZIP compression failed.")}
    return count<raw.count ? Data(compressed.prefix(Int(count))):Data(raw)
  }
  static func unpack(_ data:Data,expected:Int)throws->[UInt8] {
    if data.count==expected{return Array(data)}
    guard data.count<expected else{throw CraftError.invalid("OpenEXR block exceeds its declared sample size.")}
    var decoded=try PSDChannelCodec.inflate(data,expected:expected)
    if decoded.count>1{for i in 1..<decoded.count{decoded[i]=decoded[i-1] &+ decoded[i] &- 128}}
    var result=[UInt8](repeating:0,count:expected);let half=(expected+1)/2
    for i in result.indices{result[i]=decoded[i/2+(i%2==0 ? 0:half)]};return result
  }
  /// Scene-linear, premultiplied file colors. Zero-alpha color is retained for
  /// emissive/hidden samples rather than discarded. No SDR tone mapping.
  public static func encoded(_ source:CraftDocument,compression:Compression = .zip,
    sample:Sample = .float,transparency:Bool=true,maximumBytes:Int=maximumBytes)throws->Data {
    try source.validate();try Task.checkCancellation()
    guard source.depth == .f32,source.colorMode == .rgb,source.inkMode==nil,source.restrictedMode==nil else{throw CraftError.unsupported("OpenEXR export requires a32-bit RGB document.")}
    guard maximumBytes>0,maximumBytes<=Self.maximumBytes else{throw CraftError.invalid("Invalid OpenEXR output budget.")}
    let pixels:Surface
    if source.layers.count==1,let layer=source.layers.first,layer.visible,layer.opacity==1,layer.blendMode == .normal,layer.clipped != true,
      source.videoTimeline==nil,source.animation==nil,layer.video==nil,layer.videoTiming==nil,layer.nativeMode==nil,
      layer.x==0,layer.y==0,layer.affine==nil,layer.sourceProjection==nil,layer.warp==nil,layer.mask==nil,layer.vectorMask==nil,layer.smartObject==nil,layer.smartFilters==nil,layer.style==nil,
      case .raster(let raster)=layer.content,raster.width==source.width,raster.height==source.height {
      pixels=raster
    }else{pixels=try source.width>Surface.maximumDensePixels/source.height ? Renderer.compositePaged(source):Renderer.composite(source)}
    let target=try CraftDocument(width:source.width,height:source.height,depth:.f32)
    let surface=try ColorManagement.converted(pixels,from:source,to:target)
    return try encoded(surface,resolution:source.pixelsPerInch,compression:compression,sample:sample,transparency:transparency,maximumBytes:maximumBytes)
  }
  static func encoded(_ surface:Surface,resolution:Double=72,compression:Compression = .zip,
    sample:Sample = .float,transparency:Bool=true,maximumBytes:Int=maximumBytes)throws->Data {
    try surface.validated();try Task.checkCancellation()
    guard maximumBytes>0,maximumBytes<=Self.maximumBytes else{throw CraftError.invalid("Invalid OpenEXR output budget.")}
    guard surface.depth == .f32 else{throw CraftError.invalid("OpenEXR requires floating-point samples.")}
    let names=transparency ? ["A","B","G","R"]:["B","G","R"],w=surface.width,h=surface.height
    let rowBytes=w*names.count*sample.bytes
    guard rowBytes<=maximumBlockBytes/compression.lines else{throw CraftError.unsupported("OpenEXR scan-line block exceeds128MiB; choose one-line ZIP or no compression.")}
    var out=Writer();out.data=magic;out.i(2)
    var channels=Writer()
    for name in names{channels.text(name);channels.i(sample.code);channels.i(0);channels.i(1);channels.i(1)}
    channels.data.append(0);out.attr("channels","chlist",channels.data)
    out.attr("compression","compression",Data([UInt8(compression.code)]))
    var box=Writer();for value in [0,0,w-1,h-1]{box.i(value)}
    out.attr("dataWindow","box2i",box.data);out.attr("displayWindow","box2i",box.data)
    out.attr("lineOrder","lineOrder",Data([0]))
    var scalar=Writer();scalar.f(1);out.attr("pixelAspectRatio","float",scalar.data)
    var center=Writer();center.f(0);center.f(0);out.attr("screenWindowCenter","v2f",center.data)
    out.attr("screenWindowWidth","float",scalar.data)
    var chroma=Writer();for value in primaries{chroma.f(value)};out.attr("chromaticities","chromaticities",chroma.data)
    var density=Writer();density.f(Float(resolution));out.attr("xDensity","float",density.data);out.data.append(0)
    let table=out.data.count,blocks=(h+compression.lines-1)/compression.lines
    guard table<=maximumBytes-blocks*8 else{throw CraftError.invalid("OpenEXR header exceeds its output budget.")}
    out.data.append(Data(repeating:0,count:blocks*8))
    var constantPayload=[Int:Data]()
    for block in 0..<blocks{
      try Task.checkCancellation();let top=block*compression.lines,rows=min(compression.lines,h-top)
      if surface.tileCount==0,let payload=constantPayload[rows]{
        guard payload.count<=maximumBytes-out.data.count-8 else{throw CraftError.invalid("OpenEXR exceeds its encoded output budget.")}
        var address=Writer();address.u(UInt64(out.data.count),8);out.data.replaceSubrange(table+block*8..<table+(block+1)*8,with:address.data)
        out.i(top);out.i(payload.count);out.data.append(payload);continue
      }
      var raw=Writer();raw.data.reserveCapacity(rowBytes*rows)
      for y in top..<top+rows{try Task.checkCancellation();for name in names{for x in 0..<w{
        let p=surface.linearPixel(x:x,y:y),color:Float
        switch name{case "A":color=p.a;case "R":color=p.r;case "G":color=p.g;default:color=p.b}
        let value=name=="A" || !transparency || p.a==0 ? color:color*p.a
        guard value.isFinite else{throw CraftError.invalid("OpenEXR sample exceeds the finite range.")}
        if sample == .float{raw.f(value)}else{raw.u(UInt64(try halfBits(value)),2)}
      }}}
      let payload=try compression == .none ? raw.data:pack(Array(raw.data))
      if surface.tileCount==0{constantPayload[rows]=payload}
      guard payload.count<=maximumBytes-out.data.count-8 else{throw CraftError.invalid("OpenEXR exceeds its encoded output budget.")}
      var address=Writer();address.u(UInt64(out.data.count),8);out.data.replaceSubrange(table+block*8..<table+(block+1)*8,with:address.data)
      out.i(top);out.i(payload.count);out.data.append(payload)
    }
    try Task.checkCancellation();return out.data
  }
}
