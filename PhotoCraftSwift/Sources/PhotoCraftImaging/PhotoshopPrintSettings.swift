import Foundation
import PhotoCraftCore

/// Reads the fields whose meaning is shared with the native print workflow.
/// The original resources remain in source metadata for editable PSD/PSB saves.
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
    return settings
  }
}
