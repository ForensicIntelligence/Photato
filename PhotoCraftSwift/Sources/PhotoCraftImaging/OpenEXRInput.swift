import Foundation
import CoreGraphics
import PhotoCraftCore

extension OpenEXR {
  struct Channel {let name:String;let sample:Sample}
  struct Header {
    let channels:[Channel],compression:Compression,dataWindow:[Int],displayWindow:[Int],resolution:Double
    let offset:Int,raw:Data,attributes:[String:(String,Data)]
    var width:Int{dataWindow[2]-dataWindow[0]+1}
    var height:Int{dataWindow[3]-dataWindow[1]+1}
    var rowBytes:Int{width*channels.reduce(0){$0+$1.sample.bytes}}
  }
  static func header(_ data:Data)throws->Header {
    var r=Reader(data:data);guard try r.bytes(4)==magic,try r.u()==2 else{throw CraftError.unsupported("OpenEXR requires a single-part scan-line image; tiled/deep/multipart files remain unsupported.")}
    var attributes=[String:(String,Data)]()
    while true{
      try Task.checkCancellation();let name=try r.text();if name.isEmpty{break}
      let type=try r.text(),size=try r.i()
      guard attributes[name]==nil,attributes.count<128,size>=0,size<=1024*1024,r.offset<=1024*1024-size else{throw CraftError.invalid("Invalid or excessive OpenEXR header.")}
      attributes[name]=(type,try r.bytes(size))
    }
    func value(_ name:String,_ type:String)throws->Data{guard let attr=attributes[name],attr.0==type else{throw CraftError.invalid("Missing OpenEXR \(name) attribute.")};return attr.1}
    func box(_ name:String)throws->[Int]{let bytes=try value(name,"box2i");guard bytes.count==16 else{throw CraftError.invalid("Invalid OpenEXR window.")};var r=Reader(data:bytes);return try (0..<4).map{_ in try r.i()}}
    let window=try box("dataWindow"),display=try box("displayWindow")
    for box in [window,display]{let w=box[2]-box[0]+1,h=box[3]-box[1]+1;guard w>0,h>0,w<=Surface.maxDimension,h<=Surface.maxDimension,w<=Surface.maxPixels/h else{throw CraftError.invalid("OpenEXR window exceeds native canvas geometry.")}}
    guard abs(window[0]-display[0])<=1_000_000,abs(window[1]-display[1])<=1_000_000 else{throw CraftError.unsupported("OpenEXR data offset exceeds native layer placement.")}
    let c=try value("compression","compression"),line=try value("lineOrder","lineOrder")
    guard c.count==1,line.count==1,[0,1].contains(line[0])else{throw CraftError.invalid("Invalid OpenEXR compression/line order.")}
    let compression:Compression
    switch c[0]{case 0:compression = .none;case 2:compression = .zips;case 3:compression = .zip;default:throw CraftError.unsupported("This OpenEXR compression is not supported. Use None, ZIP per scan line or ZIP16.")}
    var channelReader=Reader(data:try value("channels","chlist")),channels=[Channel](),names=Set<String>()
    while true{
      let name=try channelReader.text();if name.isEmpty{break}
      let kind=try channelReader.i(),linear=try channelReader.bytes(4),x=try channelReader.i(),y=try channelReader.i()
      guard channels.count<4,names.insert(name).inserted,["A","B","G","R","Y"].contains(name),[1,2].contains(kind),linear[0]<=1,linear.dropFirst().allSatisfy({$0==0}),x==1,y==1 else{throw CraftError.unsupported("OpenEXR requires full-resolution RGB/Y and optional alpha HALF/FLOAT channels; additional passes and integer/subsampled channels remain unsupported.")}
      channels.append(Channel(name:name,sample:kind==1 ? .half:.float))
    }
    guard channelReader.remaining==0,(names==["R","G","B"] || names==["R","G","B","A"] || names==["Y"] || names==["Y","A"])else{throw CraftError.invalid("Incomplete OpenEXR color channels.")}
    var aspect=Reader(data:try value("pixelAspectRatio","float"));guard aspect.data.count==4,try aspect.f()==1 else{throw CraftError.unsupported("OpenEXR non-square pixel aspect ratios remain unsupported.")}
    var center=Reader(data:try value("screenWindowCenter","v2f"))
    guard center.data.count==8,try center.f().isFinite,try center.f().isFinite else{throw CraftError.invalid("Invalid OpenEXR screen window center.")}
    var screenWidth=Reader(data:try value("screenWindowWidth","float"));let sw=try screenWidth.f()
    guard screenWidth.data.count==4,sw.isFinite,sw>0 else{throw CraftError.invalid("Invalid OpenEXR screen window width.")}
    var resolution:Double=72
    if let density=attributes["xDensity"]{var p=Reader(data:density.1);guard density.0=="float",p.data.count==4 else{throw CraftError.invalid("Invalid OpenEXR density.")};resolution=Double(try p.f());guard resolution.isFinite,(1...100000).contains(resolution)else{throw CraftError.invalid("Invalid OpenEXR density.")}}
    if let chroma=attributes["chromaticities"]{
      guard chroma.0=="chromaticities",chroma.1.count==32 else{throw CraftError.invalid("Invalid OpenEXR chromaticities.")}
      var reader=Reader(data:chroma.1);let values=try (0..<8).map{_ in try reader.f()}
      guard zip(values,primaries).allSatisfy({$0.0.isFinite && abs($0.0-$0.1)<0.00001})else{throw CraftError.unsupported("This OpenEXR chromaticity set requires a color-space mapping that is not implemented. Convert to scene-linear sRGB before import.")}
    }
    return Header(channels:channels,compression:compression,dataWindow:window,displayWindow:display,resolution:resolution,offset:r.offset,raw:data.prefix(r.offset),attributes:attributes)
  }
  public static func dimensions(_ input:Data)throws->(Int,Int) {
    guard input.count<=maximumBytes else{throw CraftError.invalid("OpenEXR input exceeds its byte budget.")}
    let h=try header(input.startIndex==0 ? input:Data(input));return(h.displayWindow[2]-h.displayWindow[0]+1,h.displayWindow[3]-h.displayWindow[1]+1)
  }
  public static func read(_ input:Data,name:String="OpenEXR",rasterByteLimit:Int=1_073_741_824)throws->CraftDocument {
    try Task.checkCancellation();guard input.count<=maximumBytes,rasterByteLimit>=0,rasterByteLimit<=1_073_741_824 else{throw CraftError.invalid("OpenEXR input exceeds its byte budget.")}
    let data=input.startIndex==0 ? input:Data(input),h=try header(data),w=h.width,height=h.height
    let blocks=(height+h.compression.lines-1)/h.compression.lines,tableBytes=blocks*8
    guard tableBytes<=data.count-h.offset,h.rowBytes<=maximumBlockBytes/h.compression.lines,w*min(64,height)*16<=rasterByteLimit else{throw CraftError.unsupported("OpenEXR scan-line workspace exceeds the import budget.")}
    var table=Reader(data:data,offset:h.offset),chunks=[(Int,Int)]();chunks.reserveCapacity(blocks)
    for index in 0..<blocks{
      try Task.checkCancellation();let offset=try table.u(8)
      guard offset<=UInt64(data.count),Int(offset)>=h.offset+tableBytes,Int(offset)<=data.count-8 else{throw CraftError.invalid("Invalid OpenEXR block offset.")}
      var chunk=Reader(data:data,offset:Int(offset));let y=try chunk.i(),count=try chunk.i(),rows=min(h.compression.lines,height-index*h.compression.lines)
      guard y==h.dataWindow[1]+index*h.compression.lines,count>0,count<=h.rowBytes*rows,count<=chunk.remaining else{throw CraftError.invalid("Invalid OpenEXR scan-line block.")}
      chunks.append((Int(offset),8+count))
    }
    let sorted=chunks.sorted{$0.0<$1.0}
    for i in 1..<sorted.count{guard sorted[i-1].0+sorted[i-1].1<=sorted[i].0 else{throw CraftError.invalid("Overlapping OpenEXR blocks.")}}
    let builder=try Surface.PagedBuilder(width:w,height:height,depth:.f32,fill:.clear,colorEncoding:.linearRGB),hasAlpha=h.channels.contains{$0.name=="A"}
    for top in stride(from:0,to:height,by:64){
      try Task.checkCancellation();let rows=min(64,height-top);var band=[Float](repeating:0,count:w*rows*4)
      for block in top/h.compression.lines..<(top+rows+h.compression.lines-1)/h.compression.lines{
        let offset=chunks[block].0,blockTop=block*h.compression.lines,blockRows=min(h.compression.lines,height-blockTop)
        var chunk=Reader(data:data,offset:offset+4);let count=try chunk.i(),packed=try chunk.bytes(count)
        let raw=try h.compression == .none ? Array(packed):unpack(packed,expected:h.rowBytes*blockRows)
        guard raw.count==h.rowBytes*blockRows else{throw CraftError.invalid("OpenEXR sample count differs from its block.")}
        var samples=Reader(data:Data(raw))
        for y in blockTop..<blockTop+blockRows{try Task.checkCancellation();for channel in h.channels{for x in 0..<w{
          let value=try channel.sample == .half ? halfValue(UInt16(samples.u(2))):samples.f()
          guard value.isFinite,channel.name != "A" || (0...1).contains(value)else{throw CraftError.unsupported("OpenEXR non-finite colors or alpha outside0...1 cannot be represented without changing samples.")}
          let at=((y-top)*w+x)*4
          switch channel.name{case "R":band[at]=value;case "G":band[at+1]=value;case "B":band[at+2]=value;case "A":band[at+3]=value;default:band[at]=value;band[at+1]=value;band[at+2]=value}
        }}}
      }
      for left in stride(from:0,to:w,by:2048){
        let width=min(2048,w-left);var patch=try Surface(width:width,height:rows,depth:.f32,colorEncoding:.linearRGB)
        for y in 0..<rows{try Task.checkCancellation();for x in 0..<width{
          let at=(y*w+left+x)*4,a=hasAlpha ? band[at+3]:1
          let p=a>0 ? Pixel(band[at]/a,band[at+1]/a,band[at+2]/a,a):Pixel(band[at],band[at+1],band[at+2],a)
          guard p.isFinite else{throw CraftError.unsupported("OpenEXR unpremultiplication exceeds the finite native range.")};patch.setLinearPixel(x:x,y:y,p)
        }}
        try builder.append(patch,atX:left,atY:top)
      }
    }
    let pixels=try builder.finish(),display=h.displayWindow
    var doc=try CraftDocument(width:display[2]-display[0]+1,height:display[3]-display[1]+1,depth:.f32,name:name)
    var layer=Layer(name:name,content:.raster(pixels));layer.x=h.dataWindow[0]-display[0];layer.y=h.dataWindow[1]-display[1]
    doc.layers=[layer];doc.activeLayerID=layer.id;doc.resolution=h.resolution;doc.sourceMetadata=["exr.header":h.raw]
    try doc.validate();try Task.checkCancellation();return doc
  }
}
