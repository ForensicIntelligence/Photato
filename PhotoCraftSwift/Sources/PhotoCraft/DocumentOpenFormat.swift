import AppKit
import ImageIO
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

/// Reader selection is independent of the filename. Selection verifies the
/// container before invoking the existing decoder; it never converts the input.
enum DocumentOpenFormat: String, CaseIterable, Sendable {
  case automatic, native = "photato", pcraft, psd, psb, png, jpeg, tiff, heic, bmp, gif, raw, movie, pdf
  var title: String {
    switch self {
    case .pdf: "PDF"
    case .movie: "Movie"
    case .raw: "Camera RAW"
    case .automatic: "Automatic"
    case .native: "Photato"
    case .pcraft: "PhotoCraft Project"
    case .psd: "Photoshop"
    case .psb: "Large Document Format"
    case .png: "PNG"
    case .jpeg: "JPEG"
    case .tiff: "TIFF"
    case .heic: "HEIC"
    case .bmp: "BMP"
    case .gif: "GIF"
    }
  }
  var contentType: UTType? {
    switch self {
    case .pdf: .pdf
    case .movie: .movie
    case .raw: RawSourceIO.contentType
    case .automatic: nil
    case .native: DocumentIO.Format.native.contentType
    case .pcraft: DocumentIO.pcraftContentType
    case .psd: DocumentIO.Format.psd.contentType
    case .psb: DocumentIO.Format.psb.contentType
    case .png: .png
    case .jpeg: .jpeg
    case .tiff: .tiff
    case .heic: .heic
    case .bmp: .bmp
    case .gif: .gif
    }
  }
  var persistenceFormat: DocumentIO.Format? { .init(rawValue: rawValue) }
  func validate(_ actual: Self?) throws {
    guard self == .automatic || self == actual else {
      throw CraftError.unsupported("The file does not match the selected \(title) format.")
    }
  }
  private static func signature(_ data: Data) -> Self? {
    if data.starts(with: Data("PHOTATO\0".utf8)) || data.starts(with: Data("bplist00".utf8)) { return .native }
    if let text = String(data: data.prefix(64), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      text.hasPrefix("<?xml") || text.hasPrefix("<plist") { return .native }
    if MovieIO.recognizes(data) { return .movie }
    if data.count >= 6, data.starts(with: Data("8BPS".utf8)) {
      let bytes = Array(data.prefix(6))
      return bytes[4] == 0 ? (bytes[5] == 1 ? .psd : bytes[5] == 2 ? .psb : nil) : nil
    }
    if data.starts(with:Data("%PDF-".utf8)) {return .pdf}
    return nil
  }
  private static func imageType(_ type: CFString?) -> Self? {
    guard let type else { return nil }
    if UTType(type as String)?.conforms(to:RawSourceIO.contentType) == true { return .raw }
    switch type as String {
    case "public.png": return .png
    case "public.jpeg": return .jpeg
    case "public.tiff": return .tiff
    case "public.heic", "public.heif": return .heic
    case "com.microsoft.bmp", "public.bmp": return .bmp
    case "com.compuserve.gif": return .gif
    default: return nil
    }
  }
  static func detect(_ data: Data) -> Self? {
    if let value = signature(data) { return value }
    if PcraftImport.recognizes(data) { return .pcraft }
    if let image = CGImageSourceCreateWithData(data as CFData, nil).flatMap({imageType(CGImageSourceGetType($0))}) {return image}
    return PDFImport.recognizes(data) ? .pdf:nil
  }
  static func detect(_ url: URL) -> Self? {
    if PcraftImport.recognizes(url) { return .pcraft }
    guard url.isFileURL, let file = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? file.close() }
    let header = (try? file.read(upToCount:1024)) ?? Data()
    if let value = signature(header) {return value}
    if let image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap({imageType(CGImageSourceGetType($0))}) {return image}
    // A misleading .pdf suffix can make ImageIO's URL reader refuse a PNG.
    // Its bounded byte-header reader still identifies the actual container.
    if let image = CGImageSourceCreateWithData(header as CFData,nil).flatMap({imageType(CGImageSourceGetType($0))}) {return image}
    return PDFImport.recognizes(header) ? .pdf:nil
  }
}

@MainActor final class DocumentOpenAccessory: NSObject {
  let view = NSStackView()
  let show = NSPopUpButton()
  let formats = NSPopUpButton()
  weak var panel: NSOpenPanel?
  var format: DocumentOpenFormat { DocumentOpenFormat.allCases[formats.indexOfSelectedItem] }
  init(panel: NSOpenPanel) {
    self.panel = panel
    super.init()
    show.addItems(withTitles: ["All Readable Documents", "All Documents"])
    formats.addItems(withTitles: DocumentOpenFormat.allCases.map(\.title))
    for control in [show, formats] { control.target = self; control.action = #selector(changed) }
    show.setAccessibilityLabel("Show documents")
    formats.setAccessibilityLabel("File format")
    view.orientation = .vertical; view.alignment = .leading; view.spacing = 8
    for (label, control) in [("Show:", show), ("Format:", formats)] {
      let row = NSStackView(views: [NSTextField(labelWithString: label), control])
      row.spacing = 12; control.widthAnchor.constraint(equalToConstant: 230).isActive = true
      view.addArrangedSubview(row)
    }
    view.setFrameSize(view.fittingSize)
    view.layoutSubtreeIfNeeded()
    changed()
  }
  @objc func changed() {
    guard let panel else { return }
    let all = show.indexOfSelectedItem == 1
    panel.allowedContentTypes = all ? [] : (format.contentType.map { [$0] }
      ?? DocumentIO.readableContentTypes)
    panel.allowsOtherFileTypes = all
    panel.canChooseDirectories = format == .pcraft
  }
}
