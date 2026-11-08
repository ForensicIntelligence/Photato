import Foundation
import PhotoCraftCore

/// A small merged-composite band, rendered in bounded regions. Channel-major
/// output revisits bands instead of retaining a complete merged raster.
final class PSDCompositeRows {
  static let preferredBandPixels = 131_072
  private let document:CraftDocument
  private let transparency:Bool
  private var firstRow = -1,height = 0
  private var pixels:[Pixel] = []
  private var prepared:CraftDocument?
  private var video:VideoTransitionRenderContext?
  private var facts:CompositionFacts?
  init(_ document:CraftDocument,transparency:Bool=true) {self.document=document;self.transparency=transparency}
  private func render(_ region:IntRect) throws -> Surface {
    // Non-RGB composition keeps its separate native mode/ink path.
    guard document.colorMode == .rgb,document.inkMode == nil,document.restrictedMode == nil else {
      return try Renderer.composite(document,region:region)
    }
    if prepared == nil {
      try document.validate()
      let (snapshot,transitions) = try Renderer.preparedSources(document)
      prepared=snapshot;video=transitions
      if snapshot.width>Surface.maximumDensePixels/snapshot.height {facts=CompositionFacts(snapshot)}
    }
    return try Renderer.compositePrepared(prepared!,region:region,video:video,facts:facts)
  }
  func row(_ y:Int,channel:Int,depth:Int) throws -> [UInt8] {
    guard (0..<document.height).contains(y),(0..<4).contains(channel) else {throw CraftError.invalid("Invalid Photoshop composite row.")}
    if y < firstRow || y >= firstRow+height {
      firstRow=y;height=min(document.height-y,max(1,min(64,Self.preferredBandPixels/document.width)))
      pixels=Array(repeating:.clear,count:document.width*height)
      for x in stride(from:0,to:document.width,by:2048) {
        try Task.checkCancellation()
        let width=min(2048,document.width-x)
        let rendered=try render(IntRect(x:x,y:y,width:width,height:height))
        for py in 0..<height {for px in 0..<width {
          pixels[py*document.width+x+px] = depth == 32
            ? PSDMergedSample.encodeLinear(rendered.linearPixel(x:x+px,y:y+py),transparency:transparency)
            : PSDMergedSample.encode(rendered.pixel(x:x+px,y:y+py),depth:depth)
        }}
      }
    }
    var bytes:[UInt8]=[];bytes.reserveCapacity(document.width*(depth/8))
    for x in 0..<document.width {
      let p=pixels[(y-firstRow)*document.width+x]
      let value:Float
      switch channel {case 0:value=p.r;case 1:value=p.g;case 2:value=p.b;default:value=p.a}
      try PSDChannelCodec.append(value,depth:depth,to:&bytes)
    }
    return bytes
  }
}
