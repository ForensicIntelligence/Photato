import Foundation
import PhotoCraftCore

/// Strict source alpha/spot/Quick Mask migration. Numeric coverage never enters
/// the RGB transfer function. Out-of-canvas nondefault samples reject atomically.
enum PcraftChannels {
  static func read(_ source:PcraftNode,project:PcraftProject,document:inout CraftDocument,namespace:Data,budget:inout Int)throws {
    let channels=try source.field("channels").array()
    guard channels.count<=CraftDocument.maximumAlphaChannels else{throw source.unsupported("Too many auxiliary channels.")}
    document.alphaChannels=try channels.enumerated().map {index,node in
      try channel(node,role:"/document/channels/\(index)",id:PcraftImport.identity(namespace,role:"channel",id:UInt64(index)),project:project,document:document,budget:&budget)
    }
    if document.alphaChannels?.isEmpty==true {document.alphaChannels=nil}
    if let quick=source.optional("quick_mask") {
      let value=try channel(quick,role:"/document/quick_mask",id:PcraftImport.identity(namespace,role:"quick-mask",id:0),project:project,document:document,budget:&budget)
      guard value.spot==nil else{throw quick.unsupported("Quick Mask cannot be a spot channel.")}
      document.quickMask=value
    }
  }
  private static func channel(_ node:PcraftNode,role:String,id:UUID,project:PcraftProject,document:CraftDocument,budget:inout Int)throws->AlphaChannel {
    try node.keys("name surface spot color opacity indicates")
    let surface=try node.field("surface");try PcraftSamples.validateSchema(surface)
    guard let source=project.surfaces[role+"/surface"],source.mode=="Grayscale",!source.alpha,
      try PcraftSamples.depth(source.sample)==document.depth else{throw node.unsupported("Channels require grayscale coverage at document depth.")}
    let bytes=source.tiles.count*256*256*MemoryLayout<Pixel>.stride
    guard bytes<=budget else{throw node.unsupported("Channel storage exceeds the remaining import budget.")};budget-=bytes
    let fill=try source.defaultPixel.withUnsafeBytes {try PcraftSamples.pixel($0,at:0,depth:document.depth,gray:true,alpha:false)}
    guard (0...1).contains(fill.r)else{throw node.invalid}
    var pixels=try Surface(width:document.width,height:document.height,depth:document.depth,fill:fill)
    for (coordinate,bytes) in source.tiles {
      let left=Int(coordinate.x)*256,top=Int(coordinate.y)*256
      try bytes.withUnsafeBytes {buffer in
        for row in 0..<256 {try Task.checkCancellation();for column in 0..<256 {
          let p=try PcraftSamples.pixel(buffer,at:(row*256+column)*source.bytesPerPixel,depth:document.depth,gray:true,alpha:false)
          guard (0...1).contains(p.r)else{throw node.invalid}
          let x=left+column,y=top+row
          if x>=0,y>=0,x<document.width,y<document.height {if !p.hasSameBits(as:fill){pixels.setPixel(x:x,y:y,p)}}
          else if !p.hasSameBits(as:fill){throw node.unsupported("Off-canvas nondefault channel coverage requires an unbounded channel model.")}
        }}
      }
    }
    var options=ChannelDisplayOptions();options.color=try PcraftFills.color(node.field("color"));options.opacity=try node.field("opacity").float()
    guard let indicates=ChannelDisplayOptions.Indicates(rawValue:try node.field("indicates").string())else{throw node.invalid};options.indicates=indicates
    var spot:SpotInk?
    if let input=node.optional("spot") {let values=try input.array();guard values.count==2 else{throw input.invalid};spot=try SpotInk(color:PcraftFills.color(values[0]),solidity:values[1].float())}
    let result=AlphaChannel(id:id,name:try node.field("name").string(),pixels:pixels,options:options,spot:spot)
    try result.validate(width:document.width,height:document.height,depth:document.depth);return result
  }
}
