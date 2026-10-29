import Foundation

public struct ContentAwareEdit: Sendable {
  public let layerID: UUID
  public let output: ContentAwareOutput
  public let window: IntRect
  public let pixels: Surface
  public let selection: SelectionMask
  public init(layerID: UUID,output: ContentAwareOutput,window: IntRect,pixels: Surface,selection: SelectionMask) {
    self.layerID = layerID; self.output = output; self.window = window; self.pixels = pixels; self.selection = selection
  }
  public func applied(to original: CraftDocument) throws -> CraftDocument {
    guard selection.width == original.width, selection.height == original.height, let box = selection.bounds,
      let index = original.layers.firstIndex(where: { $0.id == layerID }), case .raster = original.layers[index].content,
      original.layers[index].smartObject == nil, pixels.width == window.width, pixels.height == window.height, pixels.depth == original.depth,
      window == window.clipped(toWidth:original.width,height:original.height), window.contains(box.x,box.y), window.contains(box.x+box.width-1,box.y+box.height-1)
    else { throw CraftError.invalid("Content-Aware Fill result does not match the document.") }
    if output == .current && original.isImageLocked(layerID) { throw CraftError.invalid("Unlock image pixels before filling the current layer.") }
    var doc = original, layer = original.layers[index]
    if output != .current {
      guard doc.layers.count < 512, !doc.ancestors(of:layerID).contains(where: { $0.protection.fullyLocks }) else { throw CraftError.invalid("Unlock the group or remove a layer before adding fill output.") }
      layer.id = UUID(); layer.locked = false; layer.protection = []; layer.visible = true
    }
    if output == .new {
      var patch = pixels
      for y in 0..<window.height { try Task.checkCancellation(); for x in 0..<window.width {
        let a = Float(selection.bytes[(y+window.y)*selection.width+x+window.x])/255
        var p = original.depth == .f32 ? pixels.linearPixel(x:x,y:y):pixels.pixel(x:x,y:y); p.a *= a
        if original.depth == .f32 { patch.setLinearPixel(x:x,y:y,p) } else { patch.setPixel(x:x,y:y,p) }
      } }
      layer = Layer(name:"Content-Aware Fill",content:.raster(patch)); layer.parentID = original.layers[index].parentID; layer.x = window.x; layer.y = window.y
    } else {
      if output == .duplicate { layer.name += " copy" }
      let preserve = output == .current && original.isTransparencyLocked(layerID)
      try ClonePainter.paintTarget(mask:false,bounds:box,on:&layer,clipping:box,preserveTransparency:preserve) { target,transform,_ in
        guard target.width <= 16_777_216/target.height else { throw CraftError.invalid("Content-Aware Fill output exceeds 16 megapixels.") }
        var changed = false
        for y in 0..<target.height { try Task.checkCancellation(); for x in 0..<target.width {
          let p = transform.point(Double(x)+0.5,Double(y)+0.5), ix = Int(floor(p.x)),iy = Int(floor(p.y))
          guard window.contains(ix,iy) else { continue }
          let k = Float(selection.bytes[iy*selection.width+ix])/255; guard k > 0 else { continue }
          let old = original.depth == .f32 ? target.linearPixel(x:x,y:y):target.pixel(x:x,y:y)
          if preserve && old.a == 0 { continue }
          let fill = original.depth == .f32 ? pixels.linearPixel(x:ix-window.x,y:iy-window.y):pixels.pixel(x:ix-window.x,y:iy-window.y)
          // Full coverage must copy samples directly; subtraction/addition loses HDR mantissa bits.
          let value = k == 1 ? Pixel(fill.r,fill.g,fill.b,preserve ? old.a:fill.a)
            : Pixel(old.r+(fill.r-old.r)*k,old.g+(fill.g-old.g)*k,old.b+(fill.b-old.b)*k,preserve ? old.a:old.a+(fill.a-old.a)*k)
          if original.depth == .f32 { target.setLinearPixel(x:x,y:y,value) } else { target.setPixel(x:x,y:y,value) }
          changed = true
        } }
        return changed
      }
    }
    if output == .current { doc.layers[index] = layer } else { doc.layers.insert(layer,at:index+1) }
    doc.activeLayerID = layer.id; doc.setCoverageSelection(selection); try doc.validate(); return doc
  }
}
