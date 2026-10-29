import Foundation
import PhotoCraftCore

public enum VariableTextEncoding: String, Codable, CaseIterable, Sendable {
  case automatic, utf8, utf16LittleEndian, utf16BigEndian, macRoman, windowsLatin1
}
public enum VariableGraphicsInput {
  public static let maximumImageFileBytes = 64 * 1024 * 1024
  public static func text(_ data: Data, encoding: VariableTextEncoding = .automatic) throws -> String {
    guard data.count <= DataDrivenGraphics.maximumMetadataBytes else { throw CraftError.invalid("The data set file exceeds 16 MiB.") }
    let selected: String.Encoding
    switch encoding {
    case .utf8: selected = .utf8
    case .utf16LittleEndian: selected = .utf16LittleEndian
    case .utf16BigEndian: selected = .utf16BigEndian
    case .macRoman: selected = .macOSRoman
    case .windowsLatin1: selected = .windowsCP1252
    case .automatic:
      if data.starts(with: [0xff, 0xfe]) { selected = .utf16LittleEndian }
      else if data.starts(with: [0xfe, 0xff]) { selected = .utf16BigEndian }
      else { selected = String(data: data, encoding: .utf8) == nil ? .windowsCP1252 : .utf8 }
    }
    guard var value = String(data: data, encoding: selected), !value.contains("\0") else {
      throw CraftError.invalid("The data file could not be decoded. Choose its text encoding.")
    }
    if value.first == "\u{feff}" { value.removeFirst() }
    return value
  }
  public static func image(_ bytes: Data, name: String, id: UUID = UUID(),
                           for target: CraftDocument) throws -> VariableImage {
    guard !bytes.isEmpty, bytes.count <= maximumImageFileBytes else { throw CraftError.invalid("Replacement image files must be at most 64 MiB.") }
    let source = try RasterIO.read(bytes, name: name)
    guard source.animation == nil, source.videoTimeline == nil else {
      throw CraftError.unsupported("Choose a still image for Pixel Replacement.")
    }
    let pixels = try ColorManagement.converted(Renderer.composite(source), from: source, to: target)
    return .init(id: id, name: name, pixels: pixels, workingICC: target.workingICC)
  }
  /// Replacement assets use their own recorded profile. Preserve their appearance
  /// when the template's working profile changes, including Assign Profile: numeric
  /// artwork samples are reassigned, but future image placement remains color-managed.
  /// Return only after every asset converts successfully; the caller commits atomically.
  public static func imagesForWorkingProfile(in document: CraftDocument) throws -> DataDrivenGraphics? {
    guard var settings = document.variables, !document.hasAuthoritativeModeStorage else { return document.variables }
    var changed = false
    for index in settings.images.indices {
      try Task.checkCancellation()
      let image = settings.images[index]
      guard image.workingICC != document.workingICC || image.pixels.depth != document.depth else { continue }
      var source = try CraftDocument(width: 1, height: 1, depth: image.pixels.depth)
      source.workingICC = image.workingICC
      settings.images[index].pixels = try ColorManagement.converted(image.pixels, from: source, to: document)
      settings.images[index].workingICC = document.workingICC
      changed = true
    }
    if changed { settings.activeDataSetID = nil }
    try settings.validate(in: document)
    return settings
  }
  /// Import into an isolated settings copy. A failed path or malformed later row
  /// never publishes earlier rows or imported assets to the user's document.
  public static func importing(_ data: Data, encoding: VariableTextEncoding = .automatic,
                               options: VariableDataImportOptions = .init(), into document: CraftDocument,
                               loadImage: (String) throws -> Data) throws -> DataDrivenGraphics {
    var settings = document.variables ?? DataDrivenGraphics()
    let text = try text(data, encoding: encoding)
    var assets: [VariableImage] = [], cache: [String: UUID] = [:]
    let rows = try VariableDataImport.dataSets(text, variables: settings, options: options) { reference in
      if let id = cache[reference] { return id }
      try Task.checkCancellation()
      guard settings.images.count + assets.count < DataDrivenGraphics.maximumImages else { throw CraftError.invalid("The template has too many replacement images.") }
      let name = URL(fileURLWithPath: reference).lastPathComponent
      let asset = try image(loadImage(reference), name: name, for: document)
      guard settings.images.reduce(0, { $0 + $1.estimatedBytes }) + assets.reduce(0, { $0 + $1.estimatedBytes }) + asset.estimatedBytes <= DataDrivenGraphics.maximumImageBytes else {
        throw CraftError.invalid("Replacement images exceed the template's 512 MiB limit.")
      }
      assets.append(asset); cache[reference] = asset.id; return asset.id
    }
    settings.images += assets
    settings.dataSets = options.replaceExisting ? rows : settings.dataSets + rows
    settings.activeDataSetID = nil
    try settings.validate(in: document)
    return settings
  }
}
