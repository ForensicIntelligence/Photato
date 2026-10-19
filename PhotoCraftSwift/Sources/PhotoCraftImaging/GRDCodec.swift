import Foundation
import PhotoCraftCore

/// A preset may contain a gradient form not yet rendered by the native engine.
/// Such entries retain their descriptor and an explicit reason; they are never replaced by black.
public struct GRDPreset: Equatable, Sendable {
  public var gradient: GradientDefinition?
  public let unavailableReason: String?
  private let sourceName: String
  fileprivate let source: Data?
  public var name: String { gradient?.name ?? sourceName }
  public init(_ gradient: GradientDefinition) {
    self.gradient = gradient
    unavailableReason = nil
    sourceName = gradient.name
    source = nil
  }
  /// Rename even an unavailable preset without replacing its preserved gradient descriptor.
  public func renamed(_ name: String) throws -> Self {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.utf16.count <= 65_535
    else { throw CraftError.invalid("Invalid gradient name.") }
    if var gradient {
      gradient.name = name
      var result = self
      result.gradient = gradient
      return result
    }
    guard let source else { throw CraftError.invalid("Missing gradient descriptor.") }
    var wrapper = try PSDDescriptor.read(source)
    guard case .object(var descriptor) = wrapper["Grad"] else {
      throw CraftError.invalid("Missing gradient descriptor.")
    }
    PSDGradient.set(&descriptor, "Nm  ", .text(Array(name.utf16) + [0]))
    PSDGradient.set(&wrapper, "Grad", .object(descriptor))
    return .init(
      gradient: nil, reason: unavailableReason, name: name, source: try wrapper.encoded())
  }
  fileprivate init(gradient: GradientDefinition?, reason: String?, name: String, source: Data) {
    self.gradient = gradient
    unavailableReason = reason
    sourceName = name
    self.source = source
  }
}

public indirect enum GRDPresetNode: Equatable, Sendable {
  case preset(Int)
  case group(String, [GRDPresetNode])
}

public struct GRDLibrary: Equatable, Sendable {
  public var presets: [GRDPreset]
  public var hierarchy: [GRDPresetNode]
  fileprivate var originalHierarchy: [GRDPresetNode]?
  fileprivate var originalTail: Data?
  fileprivate var original: Data?
  fileprivate var originalPresets: [GRDPreset]?
  public init(_ gradients: [GradientDefinition]) {
    presets = gradients.map(GRDPreset.init)
    hierarchy = gradients.indices.map(GRDPresetNode.preset)
  }
}

/// Photoshop v5 ActionDescriptor presets, with bounded parsing and lossless unchanged export.
public enum GRDCodec {
  public static let maxPresets = 10_000
  public static let maxBytes = PSDDescriptor.maxBytes + 6
  public static func read(_ data: Data) throws -> GRDLibrary {
    guard data.count <= maxBytes else { throw CraftError.invalid("Gradient file exceeds 16 MiB.") }
    var input = PSDReader(data: data)
    guard try input.string(4) == "8BGR" else {
      throw CraftError.invalid("Not a Photoshop gradient file.")
    }
    guard try input.u16() == 5 else {
      throw CraftError.unsupported("Only Photoshop version 5 gradient files are supported.")
    }
    let descriptorData = try input.bytes(input.remaining)
    let (root, consumed) = try PSDDescriptor.readPrefix(descriptorData)
    try PSDGradient.unique(root)
    guard root.classID.text == "null", case .list(let items) = root["GrdL"],
      !items.isEmpty, items.count <= maxPresets
    else { throw CraftError.invalid("Invalid gradient preset list.") }
    var presets: [GRDPreset] = []
    for item in items {
      try Task.checkCancellation()
      guard case .object(let wrapper) = item, case .object(let descriptor) = wrapper["Grad"] else {
        throw CraftError.invalid("Invalid gradient preset record.")
      }
      try PSDGradient.unique(wrapper)
      try PSDGradient.unique(descriptor)
      let name = try PSDGradient.name(descriptor)
      let gradient: GradientDefinition?
      let reason: String?
      do {
        gradient = try PSDGradient.read(descriptor, method: PSDGradient.method(in: wrapper))
        reason = nil
      } catch CraftError.unsupported(let message) {
        gradient = nil
        reason = message
      }
      presets.append(
        .init(gradient: gradient, reason: reason, name: name, source: try wrapper.encoded()))
    }
    var library = GRDLibrary([])
    library.presets = presets
    let tail = Data(descriptorData.dropFirst(consumed))
    library.hierarchy = try readHierarchy(tail, presetCount: presets.count)
    library.originalHierarchy = library.hierarchy
    library.originalTail = tail
    library.originalPresets = presets
    library.original = data
    return library
  }
  public static func write(_ library: GRDLibrary) throws -> Data {
    guard !library.presets.isEmpty, library.presets.count <= maxPresets else {
      throw CraftError.invalid("Invalid gradient preset count.")
    }
    for preset in library.presets { try preset.gradient?.validate() }
    try validateHierarchy(library.hierarchy, presetCount: library.presets.count)
    if library.presets == library.originalPresets, library.hierarchy == library.originalHierarchy,
      let original = library.original
    {
      return original
    }
    var root: PSDDescriptor
    if let data = library.original {
      root = try PSDDescriptor.readPrefix(Data(data.dropFirst(6))).descriptor
    } else {
      root = PSDDescriptor("null")
    }
    var list: [PSDValue] = []
    for preset in library.presets {
      try Task.checkCancellation()
      var wrapper = try preset.source.map { try PSDDescriptor.read($0) } ?? PSDDescriptor("Grdn")
      if let gradient = preset.gradient {
        let original = wrapper["Grad"].flatMap { value -> PSDDescriptor? in
          if case .object(let d) = value { return d }
          return nil
        }
        let old = try? original.map {
          try PSDGradient.read($0, method: PSDGradient.method(in: wrapper))
        }
        if old != gradient {
          PSDGradient.set(&wrapper, "Grad", .object(try PSDGradient.write(gradient)))
          // Classic is the absent-method interpretation of older GRD files.
          if gradient.method != .classic || wrapper["gs99"] != nil
            || wrapper["gradientsInterpolationMethod"] != nil
          {
            let key = wrapper["gs99"] != nil ? "gs99" : "gradientsInterpolationMethod"
            PSDGradient.set(&wrapper, key, PSDGradient.methodValue(gradient.method))
            if wrapper["gs99"] != nil && wrapper["gradientsInterpolationMethod"] != nil {
              PSDGradient.set(
                &wrapper, "gradientsInterpolationMethod", PSDGradient.methodValue(gradient.method))
            }
          }
        }
      } else if preset.source == nil {
        throw CraftError.invalid("Unavailable gradient has no preserved source.")
      }
      list.append(.object(wrapper))
    }
    PSDGradient.set(&root, "GrdL", .list(list))
    var output = PSDWriter()
    output.text("8BGR")
    output.n(5, 2)
    output.data.append(try root.encoded())
    if library.hierarchy == library.originalHierarchy, let tail = library.originalTail {
      output.data.append(tail)
    } else if library.hierarchy != library.presets.indices.map(GRDPresetNode.preset) {
      let descriptor = try hierarchyDescriptor(library.hierarchy).encoded()
      output.text("8BIM")
      output.text("phry")
      output.n(descriptor.count, 4)
      output.data.append(descriptor)
    }
    guard output.data.count <= maxBytes else {
      throw CraftError.invalid("Gradient file exceeds 16 MiB.")
    }
    return output.data
  }
  private static func validateHierarchy(_ nodes: [GRDPresetNode], presetCount: Int) throws {
    var indices: [Int] = []
    var count = 0
    func visit(_ nodes: [GRDPresetNode], depth: Int) throws {
      guard depth <= 64 else {
        throw CraftError.invalid("Gradient preset folders are too deeply nested.")
      }
      for node in nodes {
        count += 1
        guard count <= maxPresets * 2 else {
          throw CraftError.invalid("Too many gradient preset folders.")
        }
        switch node {
        case .preset(let index): indices.append(index)
        case .group(let name, let children):
          guard !name.isEmpty, name.utf16.count <= 65_535 else {
            throw CraftError.invalid("Invalid gradient folder name.")
          }
          try visit(children, depth: depth + 1)
        }
      }
    }
    try visit(nodes, depth: 0)
    guard indices == Array(0..<presetCount) else {
      throw CraftError.invalid("Gradient folders must reference every preset once in file order.")
    }
  }
  private static func readHierarchy(_ data: Data, presetCount: Int) throws -> [GRDPresetNode] {
    if data.isEmpty { return (0..<presetCount).map(GRDPresetNode.preset) }
    var reader = PSDReader(data: data)
    guard try reader.string(4) == "8BIM", try reader.string(4) == "phry" else {
      throw CraftError.unsupported("Unrepresented gradient preset extension.")
    }
    let descriptor = try PSDDescriptor.read(reader.bytes(reader.u32()))
    guard reader.remaining <= 3, try reader.bytes(reader.remaining).allSatisfy({ $0 == 0 }) else {
      throw CraftError.unsupported("Unrepresented gradient preset extension data.")
    }
    try PSDGradient.unique(descriptor)
    guard case .list(let list) = descriptor["hierarchy"], list.count <= maxPresets * 3 else {
      throw CraftError.invalid("Invalid gradient preset folder hierarchy.")
    }
    var stack: [(String, [GRDPresetNode])] = [("", [])]
    var index = 0
    for item in list {
      guard case .object(let d) = item else {
        throw CraftError.invalid("Invalid gradient folder record.")
      }
      try PSDGradient.unique(d)
      switch d.classID.text {
      case "Grup":
        guard stack.count <= 64 else {
          throw CraftError.invalid("Gradient folders are too deeply nested.")
        }
        stack.append((try PSDGradient.name(d), []))
      case "preset":
        stack[stack.count - 1].1.append(.preset(index))
        index += 1
        guard index <= presetCount else {
          throw CraftError.invalid("Gradient folder preset count mismatch.")
        }
      case "groupEnd":
        guard stack.count > 1 else { throw CraftError.invalid("Unbalanced gradient folder end.") }
        let group = stack.removeLast()
        stack[stack.count - 1].1.append(.group(group.0, group.1))
      default:
        throw CraftError.unsupported("Unrepresented gradient folder record: \(d.classID.text).")
      }
    }
    guard stack.count == 1 else { throw CraftError.invalid("Unclosed gradient preset folder.") }
    try validateHierarchy(stack[0].1, presetCount: presetCount)
    return stack[0].1
  }
  private static func hierarchyDescriptor(_ nodes: [GRDPresetNode]) -> PSDDescriptor {
    var list: [PSDValue] = []
    func visit(_ nodes: [GRDPresetNode]) {
      for node in nodes {
        switch node {
        case .preset: list.append(.object(PSDDescriptor("preset")))
        case .group(let name, let children):
          list.append(
            .object(PSDDescriptor("Grup", items: [.init("Nm  ", .text(Array(name.utf16) + [0]))])))
          visit(children)
          list.append(.object(PSDDescriptor("groupEnd")))
        }
      }
    }
    visit(nodes)
    return PSDDescriptor("null", items: [.init("hierarchy", .list(list))])
  }

}

/// Shared retained-stop descriptor mapping for GRD presets and PSD GdFl layers.
enum PSDGradient {
  static func unique(_ descriptor: PSDDescriptor) throws {
    guard Set(descriptor.items.map { $0.key.bytes }).count == descriptor.items.count else {
      throw CraftError.invalid("Duplicate gradient descriptor key.")
    }
  }
  static func supported(_ descriptor: PSDDescriptor, keys: Set<String>) throws {
    try unique(descriptor)
    let unknown = descriptor.items.map { $0.key.text }.filter { !keys.contains($0) }
    guard unknown.isEmpty else {
      throw CraftError.unsupported(
        "Gradient descriptor contains unrepresented settings: \(unknown.joined(separator: ", ")).")
    }
  }
  static func name(_ descriptor: PSDDescriptor) throws -> String {
    guard case .text(let units) = descriptor["Nm  "], units.count <= 65_536 else {
      throw CraftError.invalid("Missing or oversized gradient name.")
    }
    let text = String(decoding: units, as: UTF16.self).trimmingCharacters(
      in: CharacterSet(charactersIn: "\0"))
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CraftError.invalid("Empty gradient name.")
    }
    return text
  }
  static func number(_ value: PSDValue?, unit: String? = nil, fallback: Double? = nil) throws
    -> Double
  {
    if value == nil, let fallback { return fallback }
    let result: Double?
    if case .unit(let code, let bits) = value, let unit, code == Data(unit.utf8) {
      result = Double(bitPattern: bits)
    } else {
      result = value?.number
    }
    guard let result, result.isFinite else {
      throw CraftError.invalid("Invalid gradient numeric value or unit.")
    }
    return result
  }
  // The short gs99 key is used by layer styles; gradient content uses the long key.
  // Both carry gradientInterpolationMethodType, with Gcls for Classic (not Clsc).
  static func method(in descriptor: PSDDescriptor) throws -> GradientMethod {
    if let modern = descriptor["gradientsInterpolationMethod"], let legacy = descriptor["gs99"] {
      let value = try method(modern)
      guard value == (try method(legacy)) else {
        throw CraftError.invalid("Conflicting gradient interpolation methods.")
      }
      return value
    }
    return try method(descriptor["gradientsInterpolationMethod"] ?? descriptor["gs99"])
  }
  static func method(_ value: PSDValue?) throws -> GradientMethod {
    guard let value else { return .classic }
    guard case .enumerated(let type, let code) = value,
      type.text == "gradientInterpolationMethodType"
    else {
      throw CraftError.unsupported("Unrepresented gradient interpolation method.")
    }
    switch code.text {
    case "Perc": return .perceptual
    case "Lnr ": return .linear
    case "Gcls": return .classic
    case "GIMs": return .stripes
    default:
      throw CraftError.unsupported("Unrepresented gradient interpolation method: \(code.text).")
    }
  }
  static func methodValue(_ method: GradientMethod) -> PSDValue {
    .enumerated(
      PSDID("gradientInterpolationMethodType"),
      PSDID(
        method == .perceptual
          ? "Perc" : method == .linear ? "Lnr " : method == .stripes ? "GIMs" : "Gcls"))
  }
  static func set(_ descriptor: inout PSDDescriptor, _ key: String, _ value: PSDValue) {
    if let i = descriptor.items.firstIndex(where: { $0.key.text == key }) {
      descriptor.items[i].value = value
    } else {
      descriptor.items.append(.init(key, value))
    }
  }
  static func read(_ descriptor: PSDDescriptor, method: GradientMethod) throws -> GradientDefinition
  {
    guard descriptor.classID.text == "Grdn" else {
      throw CraftError.invalid("Invalid gradient descriptor class.")
    }
    let name = try name(descriptor)
    guard case .enumerated(let type, let form) = descriptor["GrdF"], type.text == "GrdF" else {
      throw CraftError.invalid("Missing gradient form.")
    }
    if form.text == "ClNs" {
      throw CraftError.unsupported(
        "Noise gradients are preserved but their native renderer is still pending.")
    }
    guard form.text == "CstS" else {
      throw CraftError.unsupported("Unrepresented gradient form: \(form.text).")
    }
    try supported(descriptor, keys: ["Nm  ", "GrdF", "Intr", "Clrs", "Trns"])
    guard case .list(let colorValues) = descriptor["Clrs"], !colorValues.isEmpty,
      colorValues.count <= GradientDefinition.maxStops
    else { throw CraftError.invalid("Invalid gradient color stop count.") }
    let opacityValues: [PSDValue]
    if let value = descriptor["Trns"] {
      guard case .list(let values) = value, values.count <= GradientDefinition.maxStops else {
        throw CraftError.invalid("Invalid gradient opacity stop count.")
      }
      opacityValues = values
    } else {
      opacityValues = []
    }
    func stop(_ value: PSDValue, classID: String, keys: Set<String>) throws -> (
      PSDDescriptor, Float, Float
    ) {
      guard case .object(let d) = value, d.classID.text == classID else {
        throw CraftError.invalid("Invalid gradient stop.")
      }
      try supported(d, keys: keys)
      let p = try number(d["Lctn"]) / 4096
      let m = try number(d["Mdpn"], fallback: 50) / 100
      guard (0...1).contains(p), (0...1).contains(m) else {
        throw CraftError.invalid("Gradient stop lies outside its range.")
      }
      return (d, Float(p), Float(m))
    }
    let colors = try colorValues.map { value -> GradientColorStop in
      let (s, position, midpoint) = try stop(
        value, classID: "Clrt", keys: ["Clr ", "Type", "Lctn", "Mdpn"])
      guard case .enumerated(let type, let code) = s["Type"], type.text == "Clry" else {
        throw CraftError.invalid("Invalid gradient color type.")
      }
      let color: GradientColor
      switch code.text {
      case "FrgC": color = .foreground
      case "BckC": color = .background
      case "UsrS":
        guard case .object(let d) = s["Clr "] else {
          throw CraftError.invalid("Missing gradient color.")
        }
        switch d.classID.text {
        case "HSBC":
          try supported(d, keys: ["H   ", "Strt", "Brgh"])
          let h = try number(d["H   "], unit: "#Ang")
          let saturation = try number(d["Strt"], unit: "#Prc") / 100
          let brightness = try number(d["Brgh"], unit: "#Prc") / 100
          guard abs(h) <= 360_000, (0...1).contains(saturation), (0...1).contains(brightness) else {
            throw CraftError.invalid("Invalid gradient HSB components.")
          }
          color = .hsb(hue: Float(h), saturation: Float(saturation), brightness: Float(brightness))
        case "Grsc":
          try supported(d, keys: ["Gry "])
          let ink = try number(d["Gry "], unit: "#Prc") / 100
          guard (0...1).contains(ink) else {
            throw CraftError.invalid("Invalid gradient grayscale component.")
          }
          color = .gray(ink: Float(ink))
        case "RGBC":
          let floating = d["redFloat"] != nil
          let keys = floating ? ["redFloat", "greenFloat", "blueFloat"] : ["Rd  ", "Grn ", "Bl  "]
          try supported(d, keys: Set(keys))
          let components = try keys.map { key -> Float in
            let component = try number(d[key]) / (floating ? 1 : 255)
            guard (0...1).contains(component) else {
              throw CraftError.invalid("Invalid gradient RGB component.")
            }
            return Float(component)
          }
          color = .rgb(Pixel(components[0], components[1], components[2]))
        default:
          throw CraftError.unsupported(
            "Gradient color model \(d.classID.text) is preserved; native conversion is pending.")
        }
      default: throw CraftError.unsupported("Unrepresented gradient color reference.")
      }
      return .init(position, color, midpoint: midpoint)
    }
    let opacity = try opacityValues.map { value -> GradientOpacityStop in
      let (s, position, midpoint) = try stop(
        value, classID: "TrnS", keys: ["Opct", "Lctn", "Mdpn"])
      let alpha = try number(s["Opct"], unit: "#Prc") / 100
      guard (0...1).contains(alpha) else { throw CraftError.invalid("Invalid gradient opacity.") }
      return .init(position, Float(alpha), midpoint: midpoint)
    }
    let smooth = try number(descriptor["Intr"], fallback: 0) / 4096
    guard (0...1).contains(smooth) else { throw CraftError.invalid("Invalid gradient smoothness.") }
    let gradient = GradientDefinition(
      name: name, colors: colors, opacity: opacity, smoothness: Float(smooth), method: method)
    try gradient.validate()
    return gradient
  }
  static func write(_ gradient: GradientDefinition) throws -> PSDDescriptor {
    try gradient.validate()
    func location(_ p: Float) -> PSDValue { .integer(Int32((p * 4096).rounded())) }
    func midpoint(_ p: Float) -> PSDValue { .integer(Int32((p * 100).rounded())) }
    let colors = gradient.colors.map { stop -> PSDValue in
      var descriptor = PSDDescriptor("Clrt")
      let code: String
      switch stop.color {
      case .foreground: code = "FrgC"
      case .background: code = "BckC"
      case .hsb(let h, let s, let b):
        code = "UsrS"
        descriptor.items.append(
          .init(
            "Clr ",
            .object(
              PSDDescriptor(
                "HSBC",
                items: [
                  .init("H   ", .unit(Data("#Ang".utf8), Double(h).bitPattern)),
                  .init("Strt", .number(Double(s) * 100)), .init("Brgh", .number(Double(b) * 100)),
                ]))))
      case .gray(let ink):
        code = "UsrS"
        descriptor.items.append(
          .init(
            "Clr ",
            .object(
              PSDDescriptor(
                "Grsc",
                items: [
                  .init("Gry ", .number(Double(ink) * 100))
                ]))))
      case .rgb(let p):
        code = "UsrS"
        descriptor.items.append(
          .init(
            "Clr ",
            .object(
              PSDDescriptor(
                "RGBC",
                items: [
                  .init("Rd  ", .number(Double(p.r) * 255)),
                  .init("Grn ", .number(Double(p.g) * 255)),
                  .init("Bl  ", .number(Double(p.b) * 255)),
                ]))))
      }
      descriptor.items += [
        .init("Type", .enumerated(PSDID("Clry"), PSDID(code))),
        .init("Lctn", location(stop.position)), .init("Mdpn", midpoint(stop.midpoint)),
      ]
      return .object(descriptor)
    }
    let stops =
      gradient.opacity.isEmpty ? [GradientOpacityStop(0, 1), .init(1, 1)] : gradient.opacity
    let opacity = stops.map { stop in
      PSDValue.object(
        PSDDescriptor(
          "TrnS",
          items: [
            .init("Opct", .unit(Data("#Prc".utf8), (Double(stop.opacity) * 100).bitPattern)),
            .init("Lctn", location(stop.position)), .init("Mdpn", midpoint(stop.midpoint)),
          ]))
    }
    return PSDDescriptor(
      "Grdn",
      items: [
        .init("Nm  ", .text(Array(gradient.name.utf16) + [0])),
        .init("GrdF", .enumerated(PSDID("GrdF"), PSDID("CstS"))),
        .init("Intr", .number(Double(gradient.smoothness) * 4096)),
        .init("Clrs", .list(colors)), .init("Trns", .list(opacity)),
      ])
  }
}
