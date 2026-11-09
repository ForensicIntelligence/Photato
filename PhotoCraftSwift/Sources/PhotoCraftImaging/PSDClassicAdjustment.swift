import Foundation
import PhotoCraftCore

/// PhotoCraft io/src/adjust_map.rs layouts, with strict bounded validation.
/// RGB Photo Filter v2 is supported; other color encodings fail explicitly.
enum PSDClassicAdjustment {
  static let keys = ["vibA", "blwh", "phfl", "mixr", "selc", "expA"]
  static func key(_ kind: ClassicAdjustment.Kind) -> String {
    switch kind { case .vibrance: "vibA"; case .blackWhite: "blwh"; case .photoFilter: "phfl"; case .channelMixer: "mixr"; case .selectiveColor: "selc"; case .exposure: "expA" }
  }
  static func read(_ data: Data, key: String) throws -> ClassicAdjustment {
    guard let index = keys.firstIndex(of:key) else { throw CraftError.unsupported("Unknown classic adjustment block.") }
    var value = ClassicAdjustment(ClassicAdjustment.Kind.allCases[index])
    var r = PSDReader(data:data)
    func integer(_ d: PSDDescriptor, _ key: String, _ fallback: Int) throws -> Int {
      guard let field = d[key] else { return fallback }
      guard let n = field.number, n.isFinite, n.rounded() == n, abs(n) <= 100_000 else { throw CraftError.invalid("Invalid adjustment integer.") }
      return Int(n)
    }
    func bool(_ d: PSDDescriptor, _ key: String, _ fallback: Bool) throws -> Bool {
      guard let field = d[key] else { return fallback }
      guard case .boolean(let b) = field else { throw CraftError.invalid("Invalid adjustment flag.") }; return b
    }
    func rgb(_ d: PSDDescriptor) throws -> Pixel {
      guard d.classID.text == "RGBC", Set(d.items.map { $0.key.text }) == ["Rd  ","Grn ","Bl  "] else { throw CraftError.unsupported("Only RGB adjustment colors are supported.") }
      let numbers = try ["Rd  ","Grn ","Bl  "].map { k -> Float in
        guard let n = d[k]?.number, n.isFinite, (0...255).contains(n) else { throw CraftError.invalid("Invalid adjustment color.") }; return Float(n/255)
      }
      return Pixel(numbers[0],numbers[1],numbers[2])
    }
    switch value.kind {
    case .exposure:
      guard [14,16].contains(data.count), try r.u16() == 1 else { throw CraftError.invalid("Invalid Exposure record.") }
      let values = try (0..<3).map { _ in Float(bitPattern: UInt32(try r.u32())) }
      guard try r.bytes(data.count-14).allSatisfy({$0 == 0}) else { throw CraftError.unsupported("Unknown Exposure padding.") }
      value.exposureSettings = .init(exposure:values[0],offset:values[1],gammaCorrection:values[2])
    case .vibrance:
      let d = try PSDDescriptor.read(data,padding:true)
      if let flag=d["useLegacy"] {
        guard case .boolean(true)=flag else {throw CraftError.unsupported("Modern Color and vibrance requires its own PSD adjustment decoder.")}
      }
      value.vibrance = try integer(d,"vibrance",0); value.saturation = try integer(d,"Strt",0)
    case .blackWhite:
      let d = try PSDDescriptor.read(data,padding:true)
      for (i,k) in ["Rd  ","Yllw","Grn ","Cyn ","Bl  ","Mgnt"].enumerated() { value.weights[i] = try integer(d,k,value.weights[i]) }
      if try bool(d,"useTint",false) {
        if case .object(let c) = d["tintColor"] { value.tint = try rgb(c) }
        else if d["tintColor"] == nil { value.tint = ClassicAdjustment.defaultTint }
        else { throw CraftError.invalid("Invalid tintColor.") }
      }
    case .photoFilter:
      guard [17,18].contains(data.count), try r.u16() == 2, try r.u16() == 0 else { throw CraftError.unsupported("Photo Filter requires a version2 RGB record.") }
      value.color = try Pixel(Float(r.u16())/65535,Float(r.u16())/65535,Float(r.u16())/65535)
      guard try r.u16() == 0 else { throw CraftError.invalid("Invalid RGB color padding.") }
      value.density = try r.u32()
      let flag = try r.u8(); guard flag <= 1 else { throw CraftError.invalid("Invalid luminosity flag.") }; value.preserveLuminosity = flag == 1
    case .channelMixer:
      guard [14,34,44].contains(data.count), try r.u16() == 1 else { throw CraftError.invalid("Invalid Channel Mixer record.") }
      let flag = try r.u16(); guard flag <= 1, flag == 1 || data.count >= 34 else { throw CraftError.invalid("Invalid mixer mode or channels.") }; value.monochrome = flag == 1
      for row in 0..<((data.count-4)/10) {
        let values = try (0..<5).map { _ in try r.i16() }
        guard values[3] == 0 else { throw CraftError.unsupported("CMYK Channel Mixer is unsupported.") }
        if row < 3 { value.matrix[row] = [values[0],values[1],values[2],values[4]] }
      }
    case .selectiveColor:
      guard data.count == 84, try r.u16() == 1 else { throw CraftError.invalid("Invalid Selective Color record.") }
      let method = try r.u16(); guard method <= 1 else { throw CraftError.invalid("Invalid Selective Color method.") }; value.relative = method == 0
      guard try r.bytes(8).allSatisfy({ $0 == 0 }) else { throw CraftError.unsupported("Reserved Selective Color range is unsupported.") }
      for row in 0..<9 { value.adjustments[row] = try (0..<4).map { _ in try r.i16() } }
    }
    try value.validate(); return value
  }
  static func write(_ value: ClassicAdjustment, original: Data? = nil) throws -> Data {
    try value.validate()
    if let original, (try? read(original,key:key(value.kind))) == value { return original }
    var w = PSDWriter()
    func rgb(_ p: Pixel) -> PSDDescriptor { .init("RGBC",items:[.init("Rd  ",.number(Double(p.r)*255)),.init("Grn ",.number(Double(p.g)*255)),.init("Bl  ",.number(Double(p.b)*255))]) }
    switch value.kind {
    case .exposure:
      guard let e = value.exposureSettings else { throw CraftError.invalid("Missing Exposure settings.") }
      w.n(1,2)
      for v in [e.exposure,e.offset,e.gammaCorrection] { w.n(Int(v.bitPattern),4) }
    case .vibrance:
      return try PSDDescriptor("null",items:[.init("vibrance",.integer(Int32(value.vibrance))),.init("Strt",.integer(Int32(value.saturation)))]).encoded()
    case .blackWhite:
      var items = zip(["Rd  ","Yllw","Grn ","Cyn ","Bl  ","Mgnt"],value.weights).map { PSDDescriptor.Item($0,.integer(Int32($1))) }
      items += [.init("useTint",.boolean(value.tint != nil)),.init("tintColor",.object(rgb(value.tint ?? ClassicAdjustment.defaultTint))),.init("bwPresetKind",.integer(1)),.init("blackAndWhitePresetFileName",.text([0]))]
      return try PSDDescriptor("null",items:items).encoded()
    case .photoFilter:
      w.n(2,2); w.n(0,2)
      for c in [value.color.r,value.color.g,value.color.b] { w.n(Int((c*65535).rounded()),2) }
      w.n(0,2); w.n(value.density,4); w.n(value.preserveLuminosity ? 1:0,1); w.n(0,1)
    case .channelMixer:
      w.n(1,2); w.n(value.monochrome ? 1:0,2)
      for row in value.matrix + [value.matrix[0]] { for v in row.prefix(3) { w.n(v,2) }; w.n(0,2); w.n(row[3],2) }
    case .selectiveColor:
      w.n(1,2); w.n(value.relative ? 0:1,2); w.n(0,8)
      for row in value.adjustments { for v in row { w.n(v,2) } }
    }
    return w.data
  }
}
