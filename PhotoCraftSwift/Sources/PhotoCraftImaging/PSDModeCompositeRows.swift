import Foundation
import PhotoCraftCore

/// Merged previews reuse the existing RGB compositor and mode conversion math,
/// retaining only a bounded band of small converted patches. Layer separations
/// are written independently, directly from their original numerical planes.
final class PSDModeCompositeRows {
  private let document: CraftDocument
  private let descriptor: DocumentModeDescriptor
  private var firstRow = -1, height = 0
  private var patches: [NativeModeRaster] = []
  init(_ document: CraftDocument) throws {
    guard let descriptor=document.modeDescriptor else {throw CraftError.invalid("Missing native mode descriptor.")}
    self.document=document;self.descriptor=descriptor
  }
  func row(_ y:Int,channel:Int,depth:Int) throws -> [UInt8] {
    guard (0..<document.height).contains(y),(0...descriptor.mode.componentCount).contains(channel),
      depth == (document.depth == .u8 ? 8:document.depth == .u16 ? 16:32) else {
      throw CraftError.invalid("Invalid Photoshop native composite row.")
    }
    if y<firstRow || y>=firstRow+height {
      firstRow=y;height=min(document.height-y,max(1,min(64,PSDCompositeRows.preferredBandPixels/document.width)))
      patches=[]
      for x in stride(from:0,to:document.width,by:2048) {
        try Task.checkCancellation()
        let region=IntRect(x:x,y:y,width:min(2048,document.width-x),height:height)
        let rendered=try Renderer.composite(document,region:region)
        let patch=try rendered.cropped(to:region)
        patches.append(try NativeModeRaster.converting(patch,to:descriptor.mode,depth:document.depth,
          profile:descriptor.profile,intent:descriptor.intent))
      }
    }
    var bytes:[UInt8]=[];bytes.reserveCapacity(document.width*(depth/8))
    for patch in patches {
      try Task.checkCancellation()
      for x in 0..<patch.width {
        try PSDChannelCodec.append(PSDModeStorage.mergedSample(patch,component:channel,index:(y-firstRow)*patch.width+x),depth:depth,to:&bytes)
      }
    }
    return bytes
  }
}
