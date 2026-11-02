import Foundation
import PhotoCraftCore

enum PcraftPatterns {
  static func read(_ node:PcraftNode,project:PcraftProject,budget:inout Int)throws->[RasterPattern] {
    let values=try node.optional("patterns")?.array() ?? []
    guard values.count<=256 else{throw node.unsupported("More than256 document patterns are not yet supported.")}
    var patterns:[RasterPattern]=[],ids=Set<String>()
    for item in values {
      try Task.checkCancellation();try item.keys("id name width height surface")
      let id=try item.field("id").string(),width=try item.field("width").integer(),height=try item.field("height").integer()
      guard ids.insert(id).inserted else{throw item.unsupported("Duplicate pattern identities cannot be remapped without changing source references.")}
      guard width>0,height>0,width<=30_000,height<=30_000,width<=RasterPattern.maxPixels/height else{throw item.unsupported("The source pattern exceeds native pattern dimensions.")}
      let surfaceNode=try item.field("surface");try PcraftSamples.validateSchema(surfaceNode)
      guard let source=project.surfaces[surfaceNode.path],["Rgb","Grayscale"].contains(source.mode)else{throw item.unsupported("This pattern color model requires a source color-management mapping.")}
      let depth=try PcraftSamples.depth(source.sample),gray=source.mode=="Grayscale"
      let initial=try source.defaultPixel.withUnsafeBytes{try PcraftSamples.pixel($0,at:0,depth:depth,gray:gray,alpha:source.alpha)}
      let expansion=source.tiles.count*256*256*MemoryLayout<Pixel>.stride
      guard expansion<=budget else{throw item.unsupported("Pattern samples exceed the remaining import budget.")};budget-=expansion
      var surface=try Surface(width:width,height:height,depth:depth,fill:initial)
      // Patterns sample their own encoded source values, including Float32 data.
      for (coordinate,bytes)in source.tiles {
        let left=Int(coordinate.x)*256,top=Int(coordinate.y)*256
        try bytes.withUnsafeBytes{buffer in
          for y in 0..<256 {
            try Task.checkCancellation()
            for x in 0..<256 {
              let value=try PcraftSamples.pixel(buffer,at:(y*256+x)*source.bytesPerPixel,depth:depth,gray:gray,alpha:source.alpha)
              let xx=left+x,yy=top+y
              if xx>=0,yy>=0,xx<width,yy<height {
                if !value.hasSameBits(as:initial){surface.setPixel(x:xx,y:yy,value)}
              }else if !value.hasSameBits(as:initial) {
                throw item.unsupported("Nondefault pattern samples outside its declared frame cannot be discarded.")
              }
            }
          }
        }
      }
      patterns.append(try RasterPattern(name:item.field("name").string(),surface:surface,id:id))
    }
    return patterns
  }
}
