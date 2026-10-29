import Foundation
import PhotoCraftCore

/// Native descriptor mapping derived from PhotoCraft io/effects_map.rs (MIT OR Apache-2.0).
/// Only represented effects/options are accepted; rich styles remain editable in native archives.
enum PSDLayerStyles {
  static let kinds: [(String, String, LayerEffect.Kind)] = [
    ("DrSh", "dropShadowMulti", .dropShadow), ("IrSh", "innerShadowMulti", .innerShadow),
    ("OrGl", "", .outerGlow), ("IrGl", "", .innerGlow),
    ("SoFi", "solidFillMulti", .colorOverlay), ("FrFX", "frameFXMulti", .stroke),
  ]
  static let blends = ["Nrml", "Dslv", "Drkn", "Mltp", "CBrn", "linearBurn", "darkerColor", "Lghn", "Scrn", "CDdg", "linearDodge", "lighterColor", "Ovrl", "SftL", "HrdL", "vividLight", "linearLight", "pinLight", "hardMix", "Dfrn", "Xclu", "blendSubtraction", "blendDivide", "H   ", "Strt", "Clr ", "Lmns"]
  static func unit(_ value: Double, _ code: String) -> PSDValue { .unit(Data(code.utf8), value.bitPattern) }
  static func enumValue(_ type: String, _ value: String) -> PSDValue { .enumerated(PSDID(type), PSDID(value)) }
  static func color(_ p: Pixel) throws -> PSDValue {
    let d = try PSDDescriptor.read(PSDSolidColor.write(p)); return d["Clr "]!
  }
  static func contour() -> PSDValue {
    .object(PSDDescriptor("ShpC", items: [.init("Nm  ", .text(Array("Linear".utf16))),
      .init("Crv ", .list([0.0,255.0].map { value in .object(PSDDescriptor("CrPt", items: [
        .init("Hrzn", .number(value)), .init("Vrtc", .number(value)), .init("Cnty", .boolean(false)),
      ])) }))]))
  }
  static func write(_ style: LayerStyle) throws -> Data {
    try style.validate()
    var items: [PSDDescriptor.Item] = [.init("Scl ", unit(style.scale,"#Prc")), .init("masterFXSwitch", .boolean(style.enabled))]
    for (single,multi,kind) in kinds {
      let effects = style.effects.filter { $0.kind == kind }
      guard effects.count <= 10, effects.count <= 1 || !multi.isEmpty else {
        throw CraftError.unsupported("This PSD effect supports fewer instances; keep the native original.")
      }
      let values = try effects.map { effect -> PSDValue in
        var fields: [PSDDescriptor.Item] = [.init("enab", .boolean(effect.enabled)), .init("present", .boolean(true)),
          .init("showInDialog", .boolean(true)), .init("Md  ", enumValue("BlnM",blends[BlendMode.allCases.firstIndex(of: effect.blendMode)!])),
          .init("Opct", unit(Double(effect.opacity)*100,"#Prc")), .init("Clr ", try color(effect.color))]
        if kind == .dropShadow || kind == .innerShadow {
          // Resolve per-style native light into explicit local PSD light. Native light editing is layer-local.
          fields += [.init("uglg", .boolean(false)), .init("lagl", unit(effect.useGlobalLight ? style.lightAngle : effect.angle,"#Ang")),
            .init("Dstn", unit(effect.distance,"#Pxl")), .init("Ckmt",unit(effect.spread,"#Pxl")),
            .init("blur",unit(effect.size,"#Pxl")), .init("Nose",unit(0,"#Prc")), .init("AntA",.boolean(false)), .init("TrnS",contour())]
          if kind == .dropShadow { fields.append(.init("layerConceals",.boolean(true))) }
        } else if kind == .outerGlow || kind == .innerGlow {
          fields += [.init("GlwT",enumValue("BETE","SfBL")), .init("Ckmt",unit(effect.spread,"#Pxl")),
            .init("blur",unit(effect.size,"#Pxl")), .init("Nose",unit(0,"#Prc")), .init("ShdN",unit(0,"#Prc")),
            .init("AntA",.boolean(false)), .init("TrnS",contour()), .init("Inpr",unit(50,"#Prc"))]
          if kind == .innerGlow { fields.append(.init("glwS",enumValue("IGSr","SrcE"))) }
        } else if kind == .stroke {
          fields += [.init("Styl",enumValue("FStl",effect.position == .inside ? "InsF" : effect.position == .center ? "CtrF" : "OutF")),
            .init("Sz  ",unit(effect.size,"#Pxl")), .init("PntT",enumValue("FrFl","SClr"))]
        }
        return .object(PSDDescriptor(single,items:fields))
      }
      if values.count == 1 { items.append(.init(single,values[0])) }
      else if !values.isEmpty { items.append(.init(multi,.list(values))) }
    }
    guard style.effects.allSatisfy({ effect in kinds.contains { $0.2 == effect.kind } }) else {
      throw CraftError.unsupported("PSD interchange currently supports shadows, glows, solid strokes and color overlays. Save other editable effects as Photato or export a flattened copy.")
    }
    return Data(repeating:0,count:4) + (try PSDDescriptor("null",items:items).encoded())
  }
  static func read(_ data: Data, globalAngle: Double = 120) throws -> LayerStyle {
    guard data.count > 4, data.prefix(4).allSatisfy({ $0 == 0 }) else { throw CraftError.invalid("Invalid PSD layer-style version.") }
    let descriptor = try PSDDescriptor.read(Data(data.dropFirst(4)),padding:true)
    let allowed = Set(["Scl ","masterFXSwitch","numModifyingFX"] + kinds.flatMap { [$0.0,$0.1] }.filter { !$0.isEmpty })
    try PSDGradient.supported(descriptor,keys:allowed)
    func flag(_ d: PSDDescriptor, _ key: String, _ fallback: Bool) throws -> Bool {
      guard let value=d[key] else { return fallback }
      guard case .boolean(let b)=value else { throw CraftError.invalid("Invalid layer-style flag.") };return b
    }
    func number(_ d: PSDDescriptor, _ key: String, _ code: String, _ fallback: Double) throws -> Double {
      try PSDGradient.number(d[key],unit:code,fallback:fallback)
    }
    func enumeration(_ d: PSDDescriptor, _ key: String, _ expected: String) throws {
      guard let value=d[key] else { return }
      guard case .enumerated(_,let code)=value,code.text==expected else { throw CraftError.unsupported("Unrepresented layer-style \(key).") }
    }
    var style=LayerStyle();style.enabled=try flag(descriptor,"masterFXSwitch",true)
    style.scale=try number(descriptor,"Scl ","#Prc",100);style.lightAngle=globalAngle
    for (single,multi,kind) in kinds {
      let values: [PSDValue]
      if !multi.isEmpty,let value=descriptor[multi] {
        guard case .list(let list)=value, (1...10).contains(list.count) else { throw CraftError.invalid("Invalid style effect list.") };values=list
      } else if let value=descriptor[single] { values=[value] } else { continue }
      for value in values {
        guard case .object(let d)=value,d.classID.text==single else { throw CraftError.invalid("Invalid style effect descriptor.") }
        let common: Set<String>=["enab","present","showInDialog","Md  ","Opct","Clr "]
        let specific: Set<String>
        switch kind {
        case .dropShadow,.innerShadow: specific=["uglg","lagl","Dstn","Ckmt","blur","Nose","AntA","TrnS","layerConceals"]
        case .innerGlow,.outerGlow: specific=["GlwT","Ckmt","blur","Nose","ShdN","AntA","TrnS","Inpr","glwS"]
        case .stroke: specific=["Styl","Sz  ","PntT","overprint"]
        default: specific=[]
        }
        try PSDGradient.supported(d,keys:common.union(specific))
        var effect=LayerEffect(kind)
        effect.enabled=try flag(d,"enab",true);effect.opacity=Float(try number(d,"Opct","#Prc",100)/100)
        if let mode=d["Md  "] {
          guard case .enumerated(_,let code)=mode,
            let index=blends.firstIndex(of:code.text) else { throw CraftError.unsupported("Unrepresented effect blend mode.") }
          effect.blendMode=BlendMode.allCases[index]
        }
        if let color=d["Clr "] { effect.color=try PSDSolidColor.read(PSDDescriptor("null",items:[.init("Clr ",color)]).encoded()) }
        if let raw=d["TrnS"] {
          guard case .object(let contour)=raw,case .list(let points)=contour["Crv "],points.count==2 else { throw CraftError.unsupported("Custom layer-effect contours are not represented.") }
          for (i,point) in points.enumerated() {
            guard case .object(let p)=point,p["Hrzn"]?.number==Double(i*255),p["Vrtc"]?.number==Double(i*255) else { throw CraftError.unsupported("Custom layer-effect contours are not represented.") }
          }
        }
        guard try !flag(d,"AntA",false), try flag(d,"layerConceals",true), try !flag(d,"overprint",false),
          try number(d,"Nose","#Prc",0)==0,try number(d,"ShdN","#Prc",0)==0,
          try number(d,"Inpr","#Prc",50)==50 else { throw CraftError.unsupported("Advanced effect contour/noise/knockout options are not represented.") }
        effect.useGlobalLight=try flag(d,"uglg",true);effect.angle=try number(d,"lagl","#Ang",120)
        effect.distance=try number(d,"Dstn","#Pxl",5);effect.spread=try number(d,"Ckmt","#Pxl",0)
        effect.size=try number(d,kind == .stroke ? "Sz  " : "blur","#Pxl",effect.size)
        if kind == .innerGlow || kind == .outerGlow { try enumeration(d,"GlwT","SfBL");try enumeration(d,"glwS","SrcE") }
        if kind == .stroke {
          try enumeration(d,"PntT","SClr")
          if case .enumerated(_,let position)=d["Styl"] {
            guard let p=["OutF":LayerEffect.StrokePosition.outside,"InsF":.inside,"CtrF":.center][position.text] else { throw CraftError.unsupported("Unrepresented stroke position.") }
            effect.position=p
          } else if d["Styl"] != nil { throw CraftError.invalid("Invalid stroke position.") }
        }
        try effect.validate();style.effects.append(effect)
      }
    }
    try style.validate();return style
  }
}
