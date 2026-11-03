import Foundation

/// Photoshop channel-to-selection and selection-to-channel combinations.
/// This differs from the geometric union/intersection used by selection tools.
public enum ChannelSelectionMath {
  public static func byte(_ old: UInt8, _ incoming: UInt8, mode: SelectionMode) -> UInt8 {
    let a = Int(old), b = Int(incoming), product = (a*b + 127)/255
    switch mode {
    case .replace: return incoming
    case .add: return UInt8(a+b-product)
    case .subtract: return UInt8(a-product)
    case .intersect: return UInt8(product)
    }
  }
  public static func coverage(_ old: Float, _ incoming: Float, mode: SelectionMode, depth: PixelDepth) -> Float {
    let a = unit(old), b = unit(incoming)
    if depth == .u8 {
      return Float(byte(UInt8((a*255).rounded()), UInt8((b*255).rounded()), mode: mode))/255
    }
    if depth == .u16 {
      let x=Int((Double(a)*32768).rounded()),y=Int((Double(b)*32768).rounded())
      let product=(x*y+16384)/32768,value:Int
      switch mode {case .replace:value=y;case .add:value=x+y-product;case .subtract:value=x-product;case .intersect:value=product}
      // Integer expansion avoids Float ties just below a16-bit half-step.
      let encoded=(value*65535+16384)/32768
      return Float(encoded)/65535
    }
    switch mode {
    case .replace: return b
    case .add: return 1-(1-a)*(1-b)
    case .subtract: return a*(1-b)
    case .intersect: return a*b
    }
  }
  public static func selection(_ incoming: SelectionMask, combining old: SelectionMask?, mode: SelectionMode) throws -> SelectionMask {
    try Task.checkCancellation()
    guard old == nil || (old?.width == incoming.width && old?.height == incoming.height) else {
      throw CraftError.invalid("Selection canvas sizes differ.")
    }
    if mode == .replace { return incoming }
    if incoming.isPaged || old?.isPaged == true {
      let previous = try old?.coverageSurface() ?? Surface(width:incoming.width,height:incoming.height,depth:.u8,fill:.black)
      let combined = try previous.combiningStoredSamples(with:incoming.coverageSurface()) { a,b in
        let v = coverage(a.r,b.r,mode:mode,depth:.u8); return Pixel(v,v,v)
      }
      return try SelectionMask(coverage:combined)
    }
    var bytes = try incoming.denseBytes()
    for i in bytes.indices {
      if i % incoming.width == 0 { try Task.checkCancellation() }
      bytes[i] = byte(old?.byte(at:i) ?? 0, bytes[i], mode:mode)
    }
    return try SelectionMask(width:incoming.width,height:incoming.height,bytes:bytes)
  }
}
