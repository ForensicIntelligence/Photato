import PhotoCraftCore

/// Artboard backgrounds use Photoshop's document-depth working grid. Owned
/// Photoshop RGB8/16/32 references qualify the quantization and linear samples.
enum ArtboardColors {
  static func grid(_ p:Pixel,scale:Double)->Pixel {
    func q(_ v:Float)->Float { Float((Double(v)*scale).rounded()/scale) }
    return Pixel(q(p.r),q(p.g),q(p.b),p.a)
  }
  static func working(_ color:Pixel,depth:PixelDepth)->Pixel {
    grid(depth == .f32 ? SRGBTransfer.linear(color):color,scale:depth == .u8 ? 255:32768)
  }
  static func fromDescriptor(_ color:Pixel,depth:PixelDepth)->Pixel {
    depth == .f32 ? SRGBTransfer.encoded(grid(color,scale:32768)):color
  }
}
