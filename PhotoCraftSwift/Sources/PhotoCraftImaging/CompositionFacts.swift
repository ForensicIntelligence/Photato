import Foundation
import PhotoCraftCore

/// Per-composition facts for one immutable prepared document. Reused across output
/// patches; never retained as mutable document state or shared between workers.
final class CompositionFacts {
  static let maximumDerivedMaskCacheBytes=512*1024*1024
  let document: CraftDocument
  private let originals: [UUID:Layer]
  private var masks: [UUID:LayerMaskSampler] = [:]
  private var preparedMasks = Set<UUID>()
  private var opaqueBases: [UUID:Bool] = [:]
  private var opaqueGroups: [UUID:Bool] = [:]
  private var retainedDerivedMaskBytes = 0

  init(_ document: CraftDocument) {
    self.document=document; originals=Dictionary(uniqueKeysWithValues:document.layers.map {($0.id,$0)})
  }
  func mask(_ layer: Layer, region: IntRect? = nil) throws -> LayerMaskSampler? {
    guard let original=originals[layer.id], original.maskProperties==layer.maskProperties,
      original.vectorMask==layer.vectorMask, original.maskCoordinateTransform==layer.maskCoordinateTransform
    else {return try LayerMaskSampler.make(layer:layer,document:document,pixelRegion:region)}
    let same: Bool
    switch (original.mask,layer.mask) {
    case (nil,nil):same=true
    case let(a?,b?):same=try a.changedTileBounds(comparedTo:b)==nil
    default:same=false
    }
    guard same else {return try LayerMaskSampler.make(layer:layer,document:document,pixelRegion:region)}
    if !preparedMasks.contains(layer.id) {
      let sampler=try LayerMaskSampler.make(layer:layer,document:document,
        pixelRegion:.init(x:0,y:0,width:document.width,height:document.height))
      let cost=derivedMaskBytes(layer,sampler:sampler)
      if cost <= Self.maximumDerivedMaskCacheBytes-retainedDerivedMaskBytes {
        masks[layer.id]=sampler;preparedMasks.insert(layer.id);retainedDerivedMaskBytes += cost
      }
      return sampler
    }
    return masks[layer.id]
  }
  private func derivedMaskBytes(_ layer: Layer,sampler:LayerMaskSampler?) -> Int {
    var total=0
    func tiled(_ w:Int,_ h:Int)->Int {((w+63)/64)*((h+63)/64)*64*64*16}
    let properties=layer.effectiveMaskProperties
    if let mask=layer.mask,properties.enabled,properties.feather>0 {
      let pad=2*Int(ceil(3*max(0.05,properties.feather)))
      total += tiled(mask.width+pad,mask.height+pad)
    }
    if let vector=layer.vectorMask,vector.enabled {
      if let source=sampler?.vectorTileSource {total += source.allocatedBytes}
      else if document.width<=Surface.maximumDensePixels/document.height {
        let pad=2*Int(ceil(vector.feather*3))
        total += 2*tiled(document.width+2*pad,document.height+2*pad)
      }
    }
    return total
  }
  func opaqueBase(_ layer: Layer?) throws -> Bool {
    guard let layer else {return false}
    if let cached=opaqueBases[layer.id] {return cached}
    let value: Bool
    if layer.opacity==1, layer.x==0, layer.y==0, layer.affine==nil,
      case .raster(let source)=layer.content,
      source.width==document.width, source.height==document.height,
      let maskUnit=try unitMask(layer) {
      value=try maskUnit && source.allStoredSamplesSatisfy {$0.a==1}
    } else {value=try RGB32NormalRenderer.hasOpaqueBase(layer,document:document)}
    opaqueBases[layer.id]=value;return value
  }
  func opaqueGroup(_ layer: Layer, firstChildOpaque: Bool) throws -> Bool {
    if let cached=opaqueGroups[layer.id] {return cached}
    var value=layer.opacity==1 && firstChildOpaque
    if value {
      if let proved=try unitMask(layer) {value=proved}
      else if let sampler=try mask(layer) {
        scan:for y in 0..<document.height {
          try Task.checkCancellation()
          for x in 0..<document.width where sampler.coverage(x:Double(x)+0.5,y:Double(y)+0.5) != 1 {
            value=false;break scan
          }
        }
      }
    }
    opaqueGroups[layer.id]=value;return value
  }
  /// Exact at aligned integer sample centers, including cropped masks with an
  /// independent outside value. Unknown geometries use the existing global test.
  private func unitMask(_ layer: Layer) throws -> Bool? {
    if let vector=layer.vectorMask,vector.enabled,vector.density != 0 {
      guard vector.feather==0,document.width>Surface.maximumDensePixels/document.height else {return nil}
      if let source=try mask(layer)?.vectorTileSource {
        guard try source.allStoredSamplesSatisfy({p in
          let value=unit(p.r)
          return (vector.density==1 ? value:1-vector.density*(1-value))==1
        }) else {return false}
      }
    }
    guard let source=layer.mask else {return true}
    let p=layer.effectiveMaskProperties
    if !p.enabled || p.density==0 {return true}
    let t=layer.maskCoordinateTransform
    guard p.feather==0,t.a==1,t.b==0,t.c==0,t.d==1,
      t.tx==t.tx.rounded(),t.ty==t.ty.rounded(),t.tx>=0,t.ty>=0,
      t.tx+Double(source.width)<=Double(document.width),
      t.ty+Double(source.height)<=Double(document.height) else {return nil}
    func unitCoverage(_ raw: Float) -> Bool {
      var value=unit(raw);if p.inverted {value=1-value}
      return (p.density==1 ? value:1-p.density*(1-value))==1
    }
    if source.width != document.width || source.height != document.height,
      !unitCoverage(p.outside) {return false}
    return try source.allStoredSamplesSatisfy { stored in
      unitCoverage(source.colorEncoding == .linearRGB ? SRGBTransfer.encoded(stored).r:stored.r)
    }
  }
}
