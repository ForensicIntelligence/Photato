import Foundation
import PhotoCraftCore

enum PSDGradientFill {
  static let styles: [(String, GradientStyle)] = [
    ("Lnr ", .linear), ("Rdl ", .radial), ("Angl", .angle), ("Rflc", .reflected),
    ("Dmnd", .diamond),
  ]
  static func read(_ data: Data) throws -> GradientFill {
    let d = try PSDDescriptor.read(data, padding: true)
    guard ["null", "gradientLayer"].contains(d.classID.text), case .object(let gradient) = d["Grad"]
    else {
      throw CraftError.unsupported("Unrepresented PSD Gradient Fill descriptor.")
    }
    try PSDGradient.supported(
      d,
      keys: [
        "Angl", "Type", "Scl ", "Grad", "Rvrs", "Dthr", "Algn", "Ofst",
        "gradientsInterpolationMethod", "gs99", "noisePreSeed",
      ])
    var fill = GradientFill(
      gradient: try PSDGradient.read(gradient, method: PSDGradient.method(in: d)))
    if let style = d["Type"] {
      guard case .enumerated(let type, let code) = style, type.text == "GrdT",
        let value = styles.first(where: { $0.0 == code.text })?.1
      else {
        throw CraftError.unsupported("Unrepresented gradient shape.")
      }
      fill.placement.style = value
    }
    // Saved descriptors omit a zero angle, independently of the New Fill UI default.
    fill.placement.angle = Float(try PSDGradient.number(d["Angl"], unit: "#Ang", fallback: 0))
    fill.placement.scale = Float(
      try PSDGradient.number(d["Scl "], unit: "#Prc", fallback: 100) / 100)
    func flag(_ key: String, _ fallback: Bool) throws -> Bool {
      guard let value = d[key] else { return fallback }
      guard case .boolean(let b) = value else { throw CraftError.invalid("Invalid gradient flag.") }
      return b
    }
    fill.aligned = try flag("Algn", true)
    fill.dither = try flag("Dthr", false)
    if let seed = d["noisePreSeed"] {
      guard case .integer = seed else {
        throw CraftError.invalid("Invalid gradient noise seed.")
      }
      guard !fill.dither else {
        throw CraftError.unsupported("Seeded Photoshop gradient dither is not yet represented.")
      }
    }
    fill.placement.reverse = try flag("Rvrs", false)
    if let value = d["Ofst"] {
      guard case .object(let point) = value, point.classID.text == "Pnt ", point.items.count == 2
      else {
        throw CraftError.unsupported("Unrepresented gradient offset.")
      }
      try PSDGradient.supported(point, keys: ["Hrzn", "Vrtc"])
      fill.placement.offsetX = Float(try PSDGradient.number(point["Hrzn"], unit: "#Prc") / 100)
      fill.placement.offsetY = Float(try PSDGradient.number(point["Vrtc"], unit: "#Prc") / 100)
    }
    try fill.validate()
    return fill
  }
  static func write(_ fill: GradientFill, original: Data? = nil) throws -> Data {
    try fill.validate()
    if let original, let decoded = try? read(original), decoded == fill { return original }
    func percent(_ x: Float) -> PSDValue { .unit(Data("#Prc".utf8), (Double(x) * 100).bitPattern) }
    let point = PSDDescriptor(
      "Pnt ",
      items: [
        .init("Hrzn", percent(fill.placement.offsetX)),
        .init("Vrtc", percent(fill.placement.offsetY)),
      ])
    var descriptor = PSDDescriptor(
      "null",
      items: [
        .init("Angl", .unit(Data("#Ang".utf8), Double(fill.placement.angle).bitPattern)),
        .init(
          "Type",
          .enumerated(PSDID("GrdT"), PSDID(styles.first { $0.1 == fill.placement.style }!.0))),
        .init("Scl ", percent(fill.placement.scale)),
        .init("Grad", .object(try PSDGradient.write(fill.gradient))),
        .init("Algn", .boolean(fill.aligned)), .init("Dthr", .boolean(fill.dither)),
        .init("Rvrs", .boolean(fill.placement.reverse)), .init("Ofst", .object(point)),
        .init("gradientsInterpolationMethod", PSDGradient.methodValue(fill.gradient.method)),
      ]
    )
    // An inactive noise seed has no effect on solid undithered fills. Retain it on edits.
    if !fill.dither, let original,
      let source = try? PSDDescriptor.read(original, padding: true),
      case .integer(let seed) = source["noisePreSeed"]
    {
      descriptor.items.append(.init("noisePreSeed", .integer(seed)))
    }
    return try descriptor.encoded()
  }
}
