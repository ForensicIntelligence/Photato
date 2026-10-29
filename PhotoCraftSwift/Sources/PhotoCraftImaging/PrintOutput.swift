import CoreGraphics
import CoreText
import Foundation
import PhotoCraftCore

/// Output settings, deliberately independent of document pixels and editing history.
public struct PrintSettings: Codable, Equatable, Sendable {
  public enum Paper: String, Codable, CaseIterable, Sendable {
    case letter, legal, tabloid, a3, a4, a5, photo4x6, photo5x7, custom
    public var size: CGSize {
      switch self {
      case .letter: CGSize(width: 612, height: 792)
      case .legal: CGSize(width: 612, height: 1008)
      case .tabloid: CGSize(width: 792, height: 1224)
      case .a3: CGSize(width: 841.89, height: 1190.55)
      case .a4: CGSize(width: 595.28, height: 841.89)
      case .a5: CGSize(width: 419.53, height: 595.28)
      case .photo4x6: CGSize(width: 288, height: 432)
      case .photo5x7: CGSize(width: 360, height: 504)
      case .custom: CGSize(width: 612, height: 792)
      }
    }
  }
  public enum Orientation: String, Codable, CaseIterable, Sendable { case portrait, landscape }
  public enum Content: String, Codable, CaseIterable, Sendable { case document, hardProof, separations }
  public enum ColorHandling: String, Codable, CaseIterable, Sendable { case printerManages, photatoManages }
  public var paper: Paper = .letter
  public var orientation: Orientation = .portrait
  public var customWidth: Double = 612
  public var customHeight: Double = 792
  /// Physical points, measured inward from the corresponding edge of the oriented paper.
  public var marginTop: Double = 18
  public var marginLeft: Double = 18
  public var marginBottom: Double = 18
  public var marginRight: Double = 18
  public var center = true
  public var scaleToFit = true
  public var scalePercent: Double = 100
  public var top: Double = 18
  public var left: Double = 18
  public var selectedArea = false
  public var copies = 1
  public var printerName = ""
  public var content: Content = .document
  public var colorHandling: ColorHandling = .printerManages
  public var profile: Data?
  public var profileName = ""
  public var intent: ModeRenderingIntent = .relativeColorimetric
  public var blackPointCompensation = true
  public var simulatePaper = false
  public var simulateBlack = false
  public var sixteenBit = false
  public var cornerCropMarks = false
  public var centerCropMarks = false
  public var registrationMarks = false
  public var labels = false
  public var description = ""
  public var border: Double = 0
  public var bleed: Double = 0
  public init() {}
  public var pageSize: CGSize {
    let base = paper == .custom ? CGSize(width: customWidth, height: customHeight) : paper.size
    return orientation == .landscape ? CGSize(width: base.height, height: base.width) : base
  }
  public func validate() throws {
    let numbers = [customWidth, customHeight, marginTop, marginLeft, marginBottom, marginRight,
      scalePercent, top, left, border, bleed]
    guard numbers.allSatisfy(\.isFinite), (18...14_400).contains(customWidth), (18...14_400).contains(customHeight),
      [marginTop, marginLeft, marginBottom, marginRight].allSatisfy({ (0...14_400).contains($0) }),
      (0.01...10_000).contains(scalePercent), abs(top) <= 144_000, abs(left) <= 144_000,
      (0...72).contains(border), (0...72).contains(bleed), (1...999).contains(copies),
      printerName.utf8.count <= 1024, profileName.utf8.count <= 1024, description.utf8.count <= 4096,
      pageSize.width > marginLeft + marginRight, pageSize.height > marginTop + marginBottom else {
      throw CraftError.invalid("Invalid print dimensions, scale, copies or margins.")
    }
    if let profile {
      let mode = try ProofSettings.mode(of: profile)
      guard mode != .lab else { throw CraftError.unsupported("Choose an RGB, CMYK or grayscale printer profile.") }
    }
    guard content != .hardProof || colorHandling == .photatoManages else {
      throw CraftError.invalid("Hard proofs require Photato-managed color and a printer profile.")
    }
    guard content == .separations || colorHandling != .photatoManages || profile != nil else {
      throw CraftError.invalid("Choose a printer/paper ICC profile for Photato-managed color.")
    }
  }
}

public struct PrintLayout: Equatable, Sendable {
  public let source: IntRect
  public let page: CGRect
  public let printable: CGRect
  public let image: CGRect
  public let scalePercent: Double
  public let effectivePPI: Double
  public var clipped: Bool { !printable.insetBy(dx: -0.001, dy: -0.001).contains(image) }
  public init(document: CraftDocument, settings: PrintSettings) throws {
    try settings.validate()
    guard document.width > 0, document.height > 0, document.width <= SoftProof.maximumPixels / document.height,
      document.pixelsPerInch.isFinite, document.pixelsPerInch > 0 else {
      throw CraftError.unsupported("Printing currently supports canvases up to8,388,608 pixels with a valid resolution.")
    }
    var crop = IntRect(x: 0, y: 0, width: document.width, height: document.height)
    if settings.selectedArea {
      guard let selected = document.selectionMask?.bounds ?? document.selection else { throw CraftError.invalid("Select an area before printing a selection.") }
      crop = selected.clipped(toWidth: document.width, height: document.height)
      guard crop.width > 0, crop.height > 0 else { throw CraftError.invalid("The selected print area is empty.") }
    }
    source = crop; page = CGRect(origin: .zero, size: settings.pageSize)
    printable = CGRect(x: settings.marginLeft, y: settings.marginBottom,
      width: page.width - settings.marginLeft - settings.marginRight,
      height: page.height - settings.marginTop - settings.marginBottom)
    let markSpace: Double = settings.cornerCropMarks || settings.centerCropMarks || settings.registrationMarks || settings.labels || settings.content == .separations || !settings.description.isEmpty ? 18 : 0
    let available = printable.insetBy(dx: markSpace + settings.border / 2, dy: markSpace + settings.border / 2)
    guard available.width > 0, available.height > 0 else { throw CraftError.invalid("The page is too small for these margins and print marks.") }
    let w = Double(crop.width) * 72 / document.pixelsPerInch, h = Double(crop.height) * 72 / document.pixelsPerInch
    let scale = settings.scaleToFit ? min(available.width / w, available.height / h) : settings.scalePercent / 100
    let width = w * scale, height = h * scale
    guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 1_440_000, height <= 1_440_000,
      settings.bleed * 2 < min(width, height) else { throw CraftError.invalid("The print size or bleed is invalid.") }
    image = CGRect(x: settings.center ? printable.midX - width / 2 : settings.left,
      y: settings.center ? printable.midY - height / 2 : page.height - settings.top - height, width: width, height: height)
    scalePercent = scale * 100; effectivePPI = document.pixelsPerInch / scale
  }
}

public struct PrintPage: Sendable {
  public let image: CGImage
  public let label: String
}
public struct PreparedPrint: Sendable {
  public let settings: PrintSettings
  public let layout: PrintLayout
  public let pages: [PrintPage]
  public let title: String
  public static let maximumBytes = 268_435_456
  public static let maximumPDFBytes = 134_217_728
  public func draw(page index: Int, in context: CGContext) {
    guard pages.indices.contains(index) else { return }
    let page = pages[index], box = layout.image
    context.saveGState(); defer { context.restoreGState() }
    context.clip(to: layout.printable.intersection(layout.page))
    context.setFillColor(gray: 1, alpha: 1); context.fill(layout.page)
    context.interpolationQuality = .high; context.draw(page.image, in: box)
    context.setStrokeColor(gray: 0, alpha: 1); context.setFillColor(gray: 0, alpha: 1)
    if settings.border > 0 { context.setLineWidth(settings.border); context.stroke(box) }
    context.setLineWidth(0.25)
    let trim = box.insetBy(dx: settings.bleed, dy: settings.bleed)
    func line(_ x: Double, _ y: Double, _ xx: Double, _ yy: Double) {
      context.move(to: CGPoint(x: x, y: y)); context.addLine(to: CGPoint(x: xx, y: yy)); context.strokePath()
    }
    if settings.cornerCropMarks {
      for x in [trim.minX, trim.maxX] { for y in [trim.minY, trim.maxY] {
        let dx: Double = x == trim.minX ? -1 : 1, dy: Double = y == trim.minY ? -1 : 1
        line(x + dx * 4, y, x + dx * 15, y); line(x, y + dy * 4, x, y + dy * 15)
      } }
    }
    if settings.centerCropMarks {
      for x in [trim.minX, trim.maxX] { let d: Double = x == trim.minX ? -1 : 1; line(x + d * 4, trim.midY, x + d * 15, trim.midY) }
      for y in [trim.minY, trim.maxY] { let d: Double = y == trim.minY ? -1 : 1; line(trim.midX, y + d * 4, trim.midX, y + d * 15) }
    }
    if settings.registrationMarks {
      for x in [box.minX - 10, box.maxX + 10] {
        context.strokeEllipse(in: CGRect(x: x - 4, y: box.midY - 4, width: 8, height: 8))
        line(x - 6, box.midY, x + 6, box.midY); line(x, box.midY - 6, x, box.midY + 6)
      }
    }
    func text(_ value: String, y: Double) {
      guard !value.isEmpty else { return }
      let font = CTFontCreateWithName("Helvetica" as CFString, 8, nil)
      let attributes = [kCTFontAttributeName as String: font, kCTForegroundColorFromContextAttributeName as String: true] as [String: Any]
      let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: Dictionary(uniqueKeysWithValues: attributes.map { (NSAttributedString.Key($0.key), $0.value) })))
      context.textMatrix = .identity; context.textPosition = CGPoint(x: box.minX, y: y); CTLineDraw(line, context)
    }
    if settings.labels || pages.count > 1 { text(title + " — " + page.label, y: box.maxY + 6) }
    text(settings.description, y: box.minY - 12)
  }
  public func pdf() throws -> Data {
    let bytes = NSMutableData()
    guard let consumer = CGDataConsumer(data: bytes), let context = CGContext(consumer: consumer, mediaBox: nil,
      [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Photato"] as CFDictionary) else { throw CraftError.invalid("Could not create print PDF.") }
    for index in pages.indices {
      try Task.checkCancellation(); var box = layout.page
      context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)] as CFDictionary)
      draw(page: index, in: context); context.endPDFPage()
      guard bytes.length <= Self.maximumPDFBytes else { throw CraftError.invalid("Print PDF exceeds128 MiB.") }
    }
    context.closePDF(); try Task.checkCancellation()
    guard bytes.length <= Self.maximumPDFBytes else { throw CraftError.invalid("Print PDF exceeds128 MiB.") }; return bytes as Data
  }
}

public enum PrintOutput {
  public static func prepare(_ document: CraftDocument, settings: PrintSettings, proof: ProofSettings = .init()) throws -> PreparedPrint {
    try Task.checkCancellation(); let layout = try PrintLayout(document: document, settings: settings), rect = layout.source
    let bits = settings.sixteenBit ? 16 : 8
    if settings.content == .separations {
      var plates: [(String, @Sendable (Int) -> Float)] = []
      if let ink = document.inkMode {
        let raster: MultichannelRaster
        switch ink { case .duotone(let value): raster = try value.separations(); case .multichannel(let value): raster = value }
        try raster.validate()
        for plate in raster.plates { plates.append((plate.name, { plate.samples.value(at: $0) })) }
      } else if let native = SoftProof.retainedComponents(document), native.mode == .cmyk {
        for (c, name) in ["Cyan", "Magenta", "Yellow", "Black"].enumerated() {
          plates.append((name, { native.value(component: c, index: $0) * native.value(component: 4, index: $0) }))
        }
      } else { throw CraftError.unsupported("Separations require retained flat CMYK, Duotone or Multichannel samples. Flatten or convert the document first.") }
      guard rect.width * rect.height * (bits / 8) <= PreparedPrint.maximumBytes / plates.count else { throw CraftError.unsupported("Prepared separation pages exceed256 MiB.") }
      let pages = try plates.map { name, sample in
        let image = try bitmap(width: rect.width, height: rect.height, bits: bits, space: CGColorSpaceCreateDeviceGray()) { y in
          (rect.x..<(rect.x + rect.width)).map { x in 1 - sample((y + rect.y) * document.width + x) }
        }
        return PrintPage(image: image, label: name)
      }
      return PreparedPrint(settings: settings, layout: layout, pages: pages, title: document.name)
    }
    let native = SoftProof.retainedComponents(document)
    let composite = try native == nil ? Renderer.composite(document) : nil
    let sourceProfile = try native?.profile ?? ColorManagement.space(for: document).copyICCData() as Data? ?? NativeModeProfile.standard(.rgb, depth: .u16)
    let sourceMode = try ProofSettings.mode(of: sourceProfile)
    // Lab bitmap encodings differ between CoreGraphics and ColorSync. Convert
    // from authoritative Lab samples to an RGB printer source, without a display preview.
    let outputProfile = try settings.colorHandling == .photatoManages ? settings.profile! : (sourceMode == .lab ? NativeModeProfile.standard(.rgb, depth: .u16) : sourceProfile)
    guard let outputSpace = CGColorSpace(iccData: outputProfile as CFData) else { throw CraftError.invalid("Could not open the printer color space.") }
    let hard = settings.content == .hardProof
    if hard { try SoftProof.validate(proof, in: document) }
    let intermediate = try hard ? proof.resolvedProfile() : outputProfile
    let first = try ProofTransform(sourceProfile, intermediate, intent: hard ? proof.intent : settings.intent, bpc: hard ? proof.blackPointCompensation : settings.blackPointCompensation)
    let second = try hard ? ProofTransform(intermediate, outputProfile,
      intent: settings.simulatePaper ? .absoluteColorimetric : .relativeColorimetric,
      bpc: !settings.simulatePaper && !settings.simulateBlack) : nil
    let bypass = hard ? proof.preserveNumbers : sourceProfile == outputProfile
    let image = try bitmap(width: rect.width, height: rect.height, bits: bits, space: outputSpace) { row in
      let y = row + rect.y; var input: [Float] = []; input.reserveCapacity(rect.width * sourceMode.componentCount)
      for x in rect.x..<(rect.x + rect.width) {
        if let native {
          let alpha = unit(native.value(component: native.mode.componentCount, index: y * document.width + x))
          for c in 0..<native.mode.componentCount {
            var value = native.value(component: c, index: y * document.width + x)
            if native.mode == .lab && c > 0 { value *= 255 / 256 }
            let white: Float = native.mode == .cmyk ? 0 : (native.mode == .lab && c > 0 ? 0.5 : 1)
            input.append(value * alpha + white * (1 - alpha))
          }
        } else if let composite {
          let p = document.depth == .f32 ? composite.linearPixel(x: x, y: y) : composite.pixel(x: x, y: y)
          input += [p.r, p.g, p.b].map { $0 * unit(p.a) + 1 - unit(p.a) }
        }
      }
      let device = try bypass ? input : first.apply(input)
      return try second?.apply(device.map(unit)) ?? device
    }
    return PreparedPrint(settings: settings, layout: layout, pages: [PrintPage(image: image, label: hard ? "Hard Proof: " + proof.displayName : "Composite")], title: document.name)
  }
  static func bitmap(width: Int, height: Int, bits: Int, space: CGColorSpace, row: (Int) throws -> [Float]) throws -> CGImage {
    let count = space.numberOfComponents, rowBytes = width * count * (bits / 8)
    guard rowBytes <= PreparedPrint.maximumBytes / height else { throw CraftError.unsupported("Prepared print image exceeds256 MiB.") }
    var bytes = Data(); bytes.reserveCapacity(rowBytes * height)
    for y in 0..<height {
      try Task.checkCancellation(); let values = try row(y)
      guard values.count == width * count, values.allSatisfy(\.isFinite) else { throw CraftError.invalid("Invalid print samples.") }
      for value in values {
        if bits == 8 { bytes.append(UInt8((unit(value) * 255).rounded())) }
        else { let n = UInt16((unit(value) * 65535).rounded()); bytes.append(UInt8(n >> 8)); bytes.append(UInt8(n & 255)) }
      }
    }
    guard let provider = CGDataProvider(data: bytes as CFData), let image = CGImage(width: width, height: height,
      bitsPerComponent: bits, bitsPerPixel: bits * count, bytesPerRow: rowBytes, space: space,
      bitmapInfo: bits == 16 ? .byteOrder16Big : [], provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
      throw CraftError.invalid("Could not create the print image.")
    }; return image
  }
}
