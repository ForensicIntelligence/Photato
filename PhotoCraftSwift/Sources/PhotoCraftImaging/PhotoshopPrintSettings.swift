import Foundation
import PhotoCraftCore

/// Maps the fields whose meaning is shared with the native print workflow.
package struct PhotoshopPrintSettings {
  private var sixteenBit: Bool?
  private var intent: ModeRenderingIntent?
  private var printerName: String?
  private var blackPointCompensation: Bool?
  private var printerManages: Bool?
  private var registrationMarks: Bool?
  private var cornerCropMarks: Bool?
  private var centerCropMarks: Bool?
  private var labels: Bool?
  private var vectorData: Bool?

  package init?(_ document: CraftDocument) {
    guard let data = document.sourceMetadata?["psdResources"],
      let blocks = try? PSDImageResources.blocks(data) else { return nil }
    func read(_ id: Int, _ kind: String) -> PSDDescriptor? {
      let matching = blocks.filter { $0.id == id }
      guard matching.count == 1, let descriptor = try? PSDDescriptor.read(matching[0].data),
        descriptor.classID.text == kind else { return nil }
      return descriptor
    }
    let output = read(1082, "printOutput"), style = read(1083, "printOutputOptions")
    guard output != nil || style != nil else { return nil }
    func flag(_ descriptor: PSDDescriptor?, _ key: String) -> Bool? {
      guard case .boolean(let value)? = descriptor?[key] else { return nil }
      return value
    }
    sixteenBit = flag(output, "printSixteenBit")
    blackPointCompensation = flag(output, "MpBl")
    printerManages = flag(output, "PstS")
    if case .enumerated(let kind, let value)? = output?["Inte"], kind.text == "Inte" {
      switch value.text {
      case "Img ": intent = .perceptual
      case "Clrm": intent = .relativeColorimetric
      default: break
      }
    }
    if case .text(let units)? = output?["printerName"], units.count <= 1025 {
      let name = String(decoding: units.prefix { $0 != 0 }, as: UTF16.self)
      if !name.isEmpty && name.utf8.count <= 1024 { printerName = name }
    }
    registrationMarks = flag(style, "RgsM")
    cornerCropMarks = flag(style, "CrnC")
    centerCropMarks = flag(style, "CntC")
    labels = flag(style, "Lbls")
    vectorData = flag(style, "vectorData")
  }

  package func applying(to defaults: PrintSettings) -> PrintSettings {
    var settings = defaults
    if let sixteenBit { settings.sixteenBit = sixteenBit }
    if let intent { settings.intent = intent }
    if let printerName { settings.printerName = printerName }
    if let blackPointCompensation { settings.blackPointCompensation = blackPointCompensation }
    if printerManages == true {
      settings.colorHandling = .printerManages
      if settings.content == .hardProof { settings.content = .document }
    }
    if let registrationMarks { settings.registrationMarks = registrationMarks }
    if let cornerCropMarks { settings.cornerCropMarks = cornerCropMarks }
    if let centerCropMarks { settings.centerCropMarks = centerCropMarks }
    if let labels { settings.labels = labels }
    if let vectorData { settings.vectorData = vectorData }
    return settings
  }

  package static func writing(_ settings: PrintSettings, to resources: Data) throws -> Data {
    let blocks = try PSDImageResources.blocks(resources)
    var output: [(String, PSDValue)] = [
      ("printSixteenBit", .boolean(settings.sixteenBit)),
      ("MpBl", .boolean(settings.blackPointCompensation)),
      ("printerName", .text(Array(settings.printerName.utf16) + [0])),
    ]
    switch settings.intent {
    case .perceptual: output.append(("Inte", .enumerated(PSDID("Inte"), PSDID("Img "))))
    case .relativeColorimetric: output.append(("Inte", .enumerated(PSDID("Inte"), PSDID("Clrm"))))
    case .saturation, .absoluteColorimetric: break
    }
    var style: [(String, PSDValue)] = [
      ("RgsM", .boolean(settings.registrationMarks)), ("CrnC", .boolean(settings.cornerCropMarks)),
      ("CntC", .boolean(settings.centerCropMarks)), ("Lbls", .boolean(settings.labels)),
    ]
    if let vectorData = settings.vectorData { style.append(("vectorData", .boolean(vectorData))) }
    var changed = [Int: Data]()
    for (id, kind, values) in [(1082, "printOutput", output), (1083, "printOutputOptions", style)] {
      let matches = blocks.filter { $0.id == id }
      // Keep ambiguous or unreadable Adobe records byte for byte.
      guard matches.count <= 1 else { continue }
      let original = matches.first
      var descriptor = PSDDescriptor(kind)
      if let original {
        guard let parsed = try? PSDDescriptor.read(original.data), parsed.classID.text == kind,
          values.allSatisfy({ key, _ in parsed.items.filter { $0.key.text == key }.count <= 1 }) else { continue }
        descriptor = parsed
      } else if id == 1082 && settings.colorHandling == .printerManages {
        descriptor.items.append(.init("PstS", .boolean(true)))
      }
      for (key, value) in values {
        if let index = descriptor.items.firstIndex(where: { $0.key.text == key }) {
          descriptor.items[index].value = value
        } else {
          descriptor.items.append(.init(key, value))
        }
      }
      changed[id] = try PSDImageResources.replacing(original, id: id, payload: descriptor.encoded())
    }
    var result = Data()
    for block in blocks { result.append(changed.removeValue(forKey: block.id) ?? block.raw) }
    for id in [1082, 1083] { if let resource = changed[id] { result.append(resource) } }
    guard result.count <= PSDImageResources.maximumBytes else { throw CraftError.invalid("PSD image metadata exceeds 16 MiB.") }
    return result
  }
}
