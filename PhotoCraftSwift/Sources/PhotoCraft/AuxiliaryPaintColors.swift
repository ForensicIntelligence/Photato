import Foundation
import Observation
import PhotoCraftCore

struct MaskPaintTarget:Hashable,Sendable {let layerID:UUID;let smartFilter:Bool}

enum PaintColorContext:String,Codable,CaseIterable {
  case image,auxiliary,mask
  var defaults:PaintColorPair {self == .mask ? PaintColorPair(foreground:.white,background:.black):PaintColorPair()}
}

struct PaintColorPair: Codable, Equatable, Sendable {
  var foreground: Pixel = .black
  var background: Pixel = .white
  var state: [String: Any] {
    ["foreground": BrushAPI.json(foreground), "background": BrushAPI.json(background)]
  }
  static var pairSchema: [String: Any] {
    ["type":"object", "additionalProperties":false, "required":["foreground","background"],
     "properties":["foreground":BrushAPI.color,"background":BrushAPI.color]]
  }
  static var stateSchema: [String: Any] {
    ["type":"object", "additionalProperties":false,
     "required":["context","active","image","auxiliary","mask"],
     "properties":["context":["type":"string","enum":PaintColorContext.allCases.map(\.rawValue)],
       "active":pairSchema,"image":pairSchema,"auxiliary":pairSchema,"mask":pairSchema]]
  }
}

/// The application controller owns one palette. Standalone editors use an isolated
/// palette; documents never encode these tool colours in their native archives.
@MainActor @Observable final class PaintPalette {
  static let key = "Photato.PaintPalette.v2"
  static let legacyKey = "Photato.PaintPalette.v1"
  private struct Archive:Codable {var version=2;var image:PaintColorPair;var auxiliary:PaintColorPair;var mask:PaintColorPair?}
  private var image=PaintColorContext.image.defaults
  private var auxiliary=PaintColorContext.auxiliary.defaults
  private var mask=PaintColorContext.mask.defaults
  private(set) var revision=0
  @ObservationIgnored private let defaults:UserDefaults?
  init(defaults:UserDefaults? = nil) {
    self.defaults=defaults
    func read(_ key:String)->Archive? {
      guard let data=defaults?.data(forKey:key),data.count<=4096,
        let value=try? JSONDecoder().decode(Archive.self,from:data),Self.valid(value.image),Self.valid(value.auxiliary) else{return nil}
      return value
    }
    if let archive=read(Self.key),archive.version==2,let mask=archive.mask,Self.valid(mask) {
      image=archive.image;auxiliary=archive.auxiliary;self.mask=mask
    } else if let legacy=read(Self.legacyKey),legacy.version==1 {
      image=legacy.image;auxiliary=legacy.auxiliary
    }
  }
  private static func valid(_ pair: PaintColorPair) -> Bool {
    [pair.foreground,pair.background].allSatisfy { p in
      [p.r,p.g,p.b,p.a].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
  }
  func colors(context:PaintColorContext)->PaintColorPair {
    switch context {case .image:return image;case .auxiliary:return auxiliary;case .mask:return mask}
  }
  func colors(auxiliary active:Bool)->PaintColorPair {colors(context:active ? .auxiliary:.image)}
  func set(_ pair:PaintColorPair,auxiliary active:Bool) {set(pair,context:active ? .auxiliary:.image)}
  func set(_ pair:PaintColorPair,context:PaintColorContext) {
    guard pair != colors(context:context) else{return}
    switch context {case .image:image=pair;case .auxiliary:auxiliary=pair;case .mask:mask=pair}
    revision+=1
    if Self.valid(image),Self.valid(auxiliary),Self.valid(mask),
      let data=try? JSONEncoder().encode(Archive(image:image,auxiliary:auxiliary,mask:mask)) {defaults?.set(data,forKey:Self.key)}
  }
  func detached()->PaintPalette {
    let result=PaintPalette();result.image=image;result.auxiliary=auxiliary;result.mask=mask;return result
  }
}

extension EditorStore {
  /// Resolve from the actual current target, including deletion/history transitions.
  var paintColorContext:PaintColorContext {
    if editingChannel != nil {return .auxiliary}
    guard let id=maskEditingLayerID,document.activeLayerID==id,
      let layer=document.layers.first(where:{$0.id==id}) else{return .image}
    return (smartFilterMaskEditing ? layer.smartFilters?.mask != nil:layer.mask != nil) ? .mask:.image
  }
  var auxiliaryPaintColorsActive:Bool {paintColorContext == .auxiliary}
  var activePaintColorPair:PaintColorPair {
    get {paintPalette.colors(context:paintColorContext)}
    set {paintPalette.set(newValue,context:paintColorContext)}
  }
  var maskPaintColorPair:PaintColorPair {
    get {paintPalette.colors(context:.mask)}
    set {paintPalette.set(newValue,context:.mask)}
  }
  var selectedMaskPaintTarget:MaskPaintTarget? {
    guard paintColorContext == .mask,let id=maskEditingLayerID else{return nil}
    return MaskPaintTarget(layerID:id,smartFilter:smartFilterMaskEditing)
  }
  func restoreMaskPaintTarget(_ target:MaskPaintTarget?) {
    guard let target,document.activeLayerID==target.layerID,
      let layer=document.layers.first(where:{$0.id==target.layerID}),
      target.smartFilter ? layer.smartFilters?.mask != nil:layer.mask != nil else{return}
    maskEditingLayerID=target.layerID;smartFilterMaskEditing=target.smartFilter
  }
  var maskEditingTargetState:Any {
    guard let target=selectedMaskPaintTarget else{return NSNull()}
    return ["kind":target.smartFilter ? "smartFilterMask":"layerMask","layerID":target.layerID.uuidString]
  }
  var imagePaintColorPair: PaintColorPair {
    get { paintPalette.colors(auxiliary: false) }
    set { paintPalette.set(newValue, auxiliary: false) }
  }
  var auxiliaryPaintColorPair: PaintColorPair {
    get { paintPalette.colors(auxiliary: true) }
    set { paintPalette.set(newValue, auxiliary: true) }
  }
  func adoptPaintPalette(_ palette: PaintPalette) {
    guard paintPalette !== palette else { return }
    let previousRevision = brushRevision
    paintPalette = palette
    brushRevision = previousRevision + 1
  }
  func detachPaintPalette() { adoptPaintPalette(paintPalette.detached()) }
  var paintColorState: [String: Any] {
    ["context":paintColorContext.rawValue,
      "active":activePaintColorPair.state,
      "image":imagePaintColorPair.state,"auxiliary":auxiliaryPaintColorPair.state,"mask":maskPaintColorPair.state]
  }
}
