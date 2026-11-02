import Foundation

/// A retained separation: pixels store density (0 = paper, 1 = ink).
/// Solidity changes only the display simulation, never separation samples.
public struct SpotInk: Codable, Equatable, Sendable {
  public var color: Pixel
  public var solidity: Float
  public init(color: Pixel = .black, solidity: Float = 0) { self.color=color; self.solidity=solidity }
  public func validate() throws {
    guard color.isFinite, color.a == 1, [color.r,color.g,color.b,solidity].allSatisfy({(0...1).contains($0)}) else {
      throw CraftError.invalid("Invalid spot color or solidity.")
    }
  }
  /// Licensed PhotoCraft overprint preview equation; not an Adobe output oracle.
  public func preview(density: Float, over p: Pixel) -> Pixel {
    let v=unit(density), keep=1-solidity*v
    func channel(_ old: Float,_ ink: Float)->Float { keep*old*(1-v+v*ink)+solidity*v*ink }
    return Pixel(channel(p.r,color.r),channel(p.g,color.g),channel(p.b,color.b),max(p.a,v))
  }
}
extension AlphaChannel {
  public func display(_ value: Float)->Float { spot == nil ? options.display(value):1-value }
  public func preview(_ value: Float, over pixel: Pixel)->Pixel {
    if let spot { return spot.preview(density:value,over:pixel) }
    let k=options.overlay(value),c=options.color
    return Pixel(pixel.r*(1-k)+c.r*k,pixel.g*(1-k)+c.g*k,pixel.b*(1-k)+c.b*k,max(pixel.a,k))
  }
}
extension CraftDocument {
  public var hasPSDChannelRetention: Bool {
    ((alphaChannels ?? [])+(quickMask.map{[$0]} ?? [])).contains{$0.psdDisplay != nil || $0.psdIdentifier != nil || $0.psdSpotGray != nil || $0.psdQuickMaskInitiallyEmpty != nil}
  }
  public var hasSpotChannels: Bool { alphaChannels?.contains(where:{$0.spot != nil}) == true }
  public func newSpotChannel(name: String, ink: SpotInk, density: Float? = nil) throws -> AlphaChannel {
    guard !colorMode.isRestricted,inkMode == nil else {throw CraftError.unsupported("Use the ink-plate workflow for this document mode.")}
    try ink.validate()
    let pixels: Surface
    if let density {
      guard density.isFinite,(0...1).contains(density)else{throw CraftError.invalid("Invalid initial ink density.")}
      pixels=try Surface(width:width,height:height,depth:depth,fill:Pixel(density,density,density))
    } else if let selection=try coverageSelection() {pixels=try AlphaChannel.coverage(selection,width:width,height:height,depth:depth)}
    else {pixels=try Surface(width:width,height:height,depth:depth,fill:.black)}
    return AlphaChannel(name:name,pixels:pixels,spot:ink)
  }
}
