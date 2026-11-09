import Foundation
import PhotoCraftCore

/// Ordinary-mode extra merged planes, independent of layer transparency.
/// PSD spot samples use editing gray; native spots retain ink density.
enum PSDAuxiliaryChannels {
  static let resourceIDs:Set<Int> = [1006,1007,1022,1045,1053,1077]
  static func all(_ document:CraftDocument)->[AlphaChannel] {
    (document.alphaChannels ?? [])+(document.quickMask.map{[$0]} ?? [])
  }
  static func imageChannels(_ header:Int,process:Int,transparency:Bool)throws->Int {
    let count=process+(transparency ? 1:0)
    guard (process...56).contains(header),header>=count,header-count <= (process == 0 ? 56 : CraftDocument.maximumAlphaChannels+1) else {
      throw CraftError.invalid("Invalid Photoshop process/transparency/auxiliary channel count.")
    };return count
  }
  static func names(_ blocks:[PSDImageResources.Block],count:Int)throws->[String] {
    var names:[String]=[]
    if let block=blocks.first(where:{$0.id==1045}) {
      var input=PSDReader(data:block.data)
      while input.remaining>0 {
        let length=try input.u32();guard names.count<count,length<=1025,length<=input.remaining/2 else{throw CraftError.invalid("Invalid auxiliary Unicode channel name.")}
        guard let name=String(data:try input.bytes(length*2),encoding:.utf16BigEndian)else{throw CraftError.invalid("Invalid Unicode channel name encoding.")}
        names.append(String(name.reversed().drop(while:{$0=="\0"}).reversed()))
      }
    } else if let block=blocks.first(where:{$0.id==1006}) {
      var input=PSDReader(data:block.data)
      while input.remaining>0 {
        guard names.count<count else{throw CraftError.invalid("Excess auxiliary channel names.")}
        let n=Int(try input.u8());guard let name=String(data:try input.bytes(n),encoding:.macOSRoman)else{throw CraftError.invalid("Invalid legacy channel name.")};names.append(name)
      }
    }
    if names.isEmpty {return (0..<count).map{"Alpha \($0+1)"}}
    guard names.count==count,names.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.utf8.count<=1024})else{throw CraftError.invalid("Auxiliary channel names disagree with the plane count.")};return names
  }
  /// Resource1022 addresses a zero-based merged plane, including process/ink planes.
  static func quickMaskInfo(_ blocks:[PSDImageResources.Block],first:Int,count:Int)throws->(index:Int?,initiallyEmpty:Bool?) {
    let entries=blocks.filter{$0.id==1022}
    guard entries.count<=1 else{throw CraftError.invalid("Duplicate Photoshop Quick Mask information.")}
    guard let block=entries.first else{return(nil,nil)}
    guard block.data.count==3 else{throw CraftError.invalid("Invalid Photoshop Quick Mask information.")}
    var input=PSDReader(data:block.data);let index=try input.u16(),flag=try input.u8()
    guard (first..<first+count).contains(index),flag<=1 else{throw CraftError.invalid("Quick Mask does not identify an auxiliary plane.")}
    return(index-first,flag != 0)
  }
  static func read(_ reader:PSDChannelReader,first:Int,count:Int,blocks:[PSDImageResources.Block],
    document:inout CraftDocument,paging:PSDRasterPaging.Context?)throws {
    if count==0 {
      guard !blocks.contains(where:{$0.id==1022})else{throw CraftError.invalid("Quick Mask has no auxiliary plane.")};return
    }
    for id in resourceIDs {guard blocks.filter({$0.id==id}).count<=1 else{throw CraftError.invalid("Duplicate Photoshop auxiliary channel resource.")}}
    let names=try names(blocks,count:count)
    let hasDisplay=blocks.contains{$0.id==1077 || $0.id==1007}
    let displays:[PSDInkChannels.Display]
    if hasDisplay {displays=try PSDInkChannels.displays(blocks,count:count)}
    else {displays=(0..<count).map{_ in .init(color:Pixel(1,0,0),opacity:0.5,kind:1,raw:Data())}}
    var identifiers:[UInt32]=[]
    if let block=blocks.first(where:{$0.id==1053}) {
      guard block.data.count==count*4 else{throw CraftError.invalid("Channel identifiers disagree with the plane count.")}
      var input=PSDReader(data:block.data)
      identifiers=try (0..<count).map{_ in UInt32(try input.u32())}
      guard Set(identifiers).count==identifiers.count else{throw CraftError.invalid("Duplicate Photoshop channel identifier.")}
    }
    let (quickIndex,initiallyEmpty)=try quickMaskInfo(blocks,first:first,count:count)
    guard count>0 else{return}
    let context=try paging ?? PSDRasterPaging.Context(heapByteLimit:512*1024*1024)
    var channels:[AlphaChannel]=[]
    for index in 0..<count {
      try Task.checkCancellation();let info=displays[index],depth=document.bitsPerChannel
      guard index != quickIndex || info.kind != 2 else{throw CraftError.invalid("Quick Mask cannot be a printing spot separation.")}
      let tiles=(document.width+63)/64*((document.height+63)/64)
      try context.admitRaster(bytes:tiles*65536)
      var sourceGray:Surface?
      let pixels:Surface
      let inverted=info.kind==2 || info.kind==0
      if inverted,depth==32 {
        let gray=try PSDRasterPaging.layer(width:document.width,height:document.height,depth:document.depth,components:1,
          fill:.black,mask:true,clampMask:false,context:context) {_ in [try reader.nextRow()]}
        sourceGray=gray;try context.admitRaster(bytes:tiles*65536)
        pixels=try PSDRasterPaging.layer(width:document.width,height:document.height,depth:document.depth,components:1,
          fill:.white,mask:true,clampMask:false,context:context) {y in
            var row:[UInt8]=[];row.reserveCapacity(document.width*4)
            for x in 0..<document.width {try PSDChannelCodec.append(1-gray.pixel(x:x,y:y).r,depth:32,to:&row)}
            return [row]
          }
      }else{
        pixels=try PSDRasterPaging.layer(width:document.width,height:document.height,depth:document.depth,components:1,
          fill:.black,mask:true,clampMask:false,context:context) {_ in
            var row=try reader.nextRow()
            if inverted {
              if depth==8 {row=row.map{255-$0}}
              else {for x in 0..<document.width {let at=x*2,n=65535-(Int(row[at])<<8|Int(row[at+1]));row[at]=UInt8(n>>8);row[at+1]=UInt8(n&255)}}
            };return [row]
          }
      }
      var options=ChannelDisplayOptions();options.color=info.color;options.opacity=info.opacity;options.indicates=info.kind==0 ? .selectedAreas:.maskedAreas
      var channel=AlphaChannel(name:names[index],pixels:pixels,options:options,spot:info.kind==2 ? SpotInk(color:info.color,solidity:info.opacity):nil)
      channel.psdDisplay=info.raw.isEmpty ? nil:info.raw
      if !identifiers.isEmpty{channel.psdIdentifier=identifiers[index]}
      channel.psdSpotGray=info.kind==2 ? sourceGray:nil
      channel.psdSelectedGray=info.kind==0 ? sourceGray:nil
      if index==quickIndex {channel.psdQuickMaskInitiallyEmpty=initiallyEmpty;document.quickMask=channel}
      else{channels.append(channel)}
    }
    guard channels.count<=document.auxiliaryChannelLimit else{throw CraftError.invalid("Too many saved alpha/spot channels.")}
    document.alphaChannels=channels.isEmpty ? nil:channels
  }
  static func resources(_ document:CraftDocument,first:Int)throws->Data {
    let channels=all(document);guard !channels.isEmpty else{return Data()}
    var names=PSDWriter(),legacy=PSDWriter(),display=PSDWriter(),ids=PSDWriter();display.n(1,4)
    var used=Set(channels.compactMap(\.psdIdentifier)),next:UInt32=1
    for channel in channels {
      let units=Array(channel.name.utf16);names.n(units.count+1,4);for u in units{names.n(Int(u),2)};names.n(0,2)
      let bytes=Data((channel.name.data(using:.macOSRoman,allowLossyConversion:true) ?? Data("Channel".utf8)).prefix(255));legacy.n(bytes.count,1);legacy.data+=bytes
      let color=channel.spot?.color ?? channel.options.color,opacity=channel.spot?.solidity ?? channel.options.opacity
      let kind=channel.spot != nil ? 2:(channel.options.indicates == .selectedAreas ? 0:1)
      if let raw=channel.psdDisplay,let old=try? PSDInkChannels.display(raw),old.color==color,old.opacity==opacity,old.kind==kind {display.data+=raw}
      else{display.data+=try PSDInkChannels.record(id:channel.id,color:color,opacity:opacity,kind:kind,document:document)}
      let identifier:UInt32
      if let original=channel.psdIdentifier{identifier=original}
      else{while used.contains(next){next+=1};identifier=next;used.insert(next)}
      ids.n(Int(identifier),4)
    }
    var result=PSDImageResources.block(1006,data:legacy.data)+PSDImageResources.block(1045,data:names.data)+PSDImageResources.block(1077,data:display.data)+PSDImageResources.block(1053,data:ids.data)
    if let quick=document.quickMask {
      var info=PSDWriter();info.n(first+channels.count-1,2);info.n(quick.psdQuickMaskInitiallyEmpty==true ? 1:0,1);result+=PSDImageResources.block(1022,data:info.data)
    };return result
  }
  static func row(_ channel:AlphaChannel,y:Int,depth:Int)throws->[UInt8] {
    var row:[UInt8]=[];row.reserveCapacity(channel.pixels.width*(depth/8))
    for x in 0..<channel.pixels.width {
      let value=channel.pixels.pixel(x:x,y:y).r
      let gray:Float
      if channel.spot==nil,channel.options.indicates != .selectedAreas{gray=value}
      else if depth==8{gray=Float(255-Int((unit(value)*255).rounded()))/255}
      else if depth==16{gray=Float(65535-Int((unit(value)*65535).rounded()))/65535}
      else if let original=(channel.spot == nil ? channel.psdSelectedGray:channel.psdSpotGray)?.pixel(x:x,y:y).r,(1-original).bitPattern==value.bitPattern{gray=original}
      else{gray=1-value}
      try PSDChannelCodec.append(gray,depth:depth,to:&row)
    };return row
  }
  /// Keep all56 Photoshop channels when an opaque image needs no merged alpha.
  /// Only the boundary case needs this bounded row preflight.
  static func mergedTransparency(_ document:CraftDocument)throws->Bool {
    let count=all(document).count,components=document.colorMode.componentCount
    if document.colorMode == .rgb,let background=document.layers.first,background.isBackground,background.visible{return false}
    if components+1+count<=56{return true}
    guard components+count==56 else{throw CraftError.invalid("Photoshop files support at most56 total channels.")}
    let rows=PSDCompositeRows(document)
    for y in 0..<document.height {
      let row=try rows.row(y,channel:3,depth:32)
      for x in 0..<document.width {guard try PSDChannelCodec.sample(row,x,depth:32)==1 else{throw CraftError.unsupported("A transparent process image and these separations exceed Photoshop's56-channel limit.")}}
    };return false
  }
}
