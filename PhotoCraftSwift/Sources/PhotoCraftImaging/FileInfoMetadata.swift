import Foundation
import ImageIO
import PhotoCraftCore

/// Uses Apple's XMP implementation; edits only requested properties and keeps
/// unrelated namespaces and localized alternatives. Raw packets survive no-ops.
public enum FileInfoMetadata {
  public static let maximumPacketBytes = 16 * 1024 * 1024
  public static func packet(_ document: CraftDocument) throws -> Data? {
    try RasterMetadata.xmpData(document.sourceMetadata)
  }
  private static func metadata(_ document: CraftDocument) throws -> CGImageMetadata? {
    guard let data = try packet(document) else { return nil }
    guard data.count <= maximumPacketBytes, let value = CGImageMetadataCreateFromXMPData(data as CFData) else {
      throw CraftError.invalid("The document contains invalid XMP metadata.")
    }
    return value
  }
  public static func read(_ document: CraftDocument) throws -> FileInformation {
    let metadata = try metadata(document)
    func string(_ path: String) -> String {
      guard let metadata else { return "" }
      return CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString) as String? ?? ""
    }
    func array(_ path: String) -> [String] {
      guard let metadata, let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) else { return [] }
      if let tags = CGImageMetadataTagCopyValue(tag) as? [CGImageMetadataTag] {
        return tags.compactMap { CGImageMetadataTagCopyValue($0) as? String }
      }
      let value = string(path); return value.isEmpty ? [] : [value]
    }
    var result = FileInformation()
    func localized(_ path: String) -> String {
      if let metadata, CGImageMetadataCopyTagWithPath(metadata, nil, (path + "[x-default]") as CFString) != nil { return string(path + "[x-default]") }
      return string(path)
    }
    result.title = localized("dc:title"); result.description = localized("dc:description"); result.copyright = localized("dc:rights")
    result.author = array("dc:creator").joined(separator: "; ")
    result.keywords = array("dc:subject")
    result.authorTitle = string("photoshop:AuthorsPosition")
    result.copyrightUrl = string("xmpRights:WebStatement")
    switch string("xmpRights:Marked").lowercased() {
    case "true", "1": result.copyrightStatus = .copyrighted
    case "false", "0": result.copyrightStatus = .publicDomain
    default: break
    }
    // Raster formats may contain IPTC/TIFF descriptions without an XMP packet.
    if let bytes = document.sourceMetadata?[RasterMetadata.propertiesKey], bytes.count <= maximumPacketBytes,
      let properties = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) as? [String: Any] {
      let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
      let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
      func text(_ value: Any?) -> String { (value as? String) ?? (value as? [String])?.joined(separator: "; ") ?? "" }
      if result.title.isEmpty { result.title = text(iptc[kCGImagePropertyIPTCObjectName as String]) }
      if result.author.isEmpty { result.author = text(iptc[kCGImagePropertyIPTCByline as String] ?? tiff[kCGImagePropertyTIFFArtist as String]) }
      if result.authorTitle.isEmpty { result.authorTitle = text(iptc[kCGImagePropertyIPTCBylineTitle as String]) }
      if result.description.isEmpty { result.description = text(iptc[kCGImagePropertyIPTCCaptionAbstract as String] ?? tiff[kCGImagePropertyTIFFImageDescription as String]) }
      if result.copyright.isEmpty { result.copyright = text(iptc[kCGImagePropertyIPTCCopyrightNotice as String] ?? tiff[kCGImagePropertyTIFFCopyright as String]) }
      if result.keywords.isEmpty { result.keywords = iptc[kCGImagePropertyIPTCKeywords as String] as? [String] ?? [] }
    }
    return result
  }
  public static func applying(_ info: FileInformation, fields: Set<String>, to document: CraftDocument) throws -> CraftDocument {
    try info.validate()
    guard fields.isSubset(of: Set(FileInformation.fields)) else { throw CraftError.invalid("Unknown File Info field.") }
    let fields = fields.intersection(info.changedFields(from: try read(document)))
    guard !fields.isEmpty else { return document }
    let original = try metadata(document)
    let metadata = original.flatMap(CGImageMetadataCreateMutableCopy) ?? CGImageMetadataCreateMutable()
    func remove(_ path: String) { _ = CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString) }
    func scalar(_ path: String, _ value: String) throws {
      if value.isEmpty && !path.hasSuffix("[x-default]") { remove(path); return }
      guard CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, value as CFString) else {
        throw CraftError.invalid("Could not update File Info property \(path).")
      }
    }
    func array(_ path: String, _ values: [String], _ type: CGImageMetadataType) throws {
      if values.isEmpty { remove(path); return }
      let parts = path.split(separator: ":")
      let tag = CGImageMetadataTagCreate("http://purl.org/dc/elements/1.1/" as CFString, "dc" as CFString,
        String(parts[1]) as CFString, type, values as CFArray)
      guard let tag, CGImageMetadataSetTagWithPath(metadata, nil, path as CFString, tag) else {
        throw CraftError.invalid("Could not update File Info array \(path).")
      }
    }
    for (key, path, value) in [("title", "dc:title[x-default]", info.title),
      ("description", "dc:description[x-default]", info.description), ("copyright", "dc:rights[x-default]", info.copyright),
      ("authorTitle", "photoshop:AuthorsPosition", info.authorTitle), ("copyrightUrl", "xmpRights:WebStatement", info.copyrightUrl)] where fields.contains(key) {
      try scalar(path, value)
    }
    if fields.contains("author") {
      let authors = info.author.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
      try array("dc:creator", authors, .arrayOrdered)
    }
    if fields.contains("keywords") { try array("dc:subject", info.keywords, .arrayUnordered) }
    if fields.contains("copyrightStatus") {
      try scalar("xmpRights:Marked", info.copyrightStatus == .unknown ? "" : info.copyrightStatus == .copyrighted ? "True" : "False")
    }
    guard let packet = CGImageMetadataCreateXMPData(metadata, nil) as Data?, packet.count <= maximumPacketBytes else {
      throw CraftError.invalid("Could not encode File Info within the XMP limit.")
    }
    var result = document, source = document.sourceMetadata ?? [:]
    source[RasterMetadata.xmpKey] = packet
    var properties: [String: Any] = [:]
    if let bytes = source[RasterMetadata.propertiesKey] {
      guard bytes.count <= maximumPacketBytes, let dictionary = try PropertyListSerialization.propertyList(from: bytes, options: [], format: nil) as? [String: Any] else { throw CraftError.invalid("Invalid stored image metadata.") }
      properties = dictionary
    }
    var iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
    var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
    for (key, tag, value) in [("title", kCGImagePropertyIPTCObjectName, info.title), ("authorTitle", kCGImagePropertyIPTCBylineTitle, info.authorTitle),
      ("description", kCGImagePropertyIPTCCaptionAbstract, info.description), ("copyright", kCGImagePropertyIPTCCopyrightNotice, info.copyright)] where fields.contains(key) { iptc[tag as String] = value }
    if fields.contains("keywords") { iptc[kCGImagePropertyIPTCKeywords as String] = info.keywords }
    if fields.contains("author") { iptc[kCGImagePropertyIPTCByline as String] = info.author.split(separator: ";").map(String.init); tiff[kCGImagePropertyTIFFArtist as String] = info.author }
    if fields.contains("copyright") { tiff[kCGImagePropertyTIFFCopyright as String] = info.copyright }
    if fields.contains("description") { tiff[kCGImagePropertyTIFFImageDescription as String] = info.description }
    properties[kCGImagePropertyIPTCDictionary as String] = iptc; properties[kCGImagePropertyTIFFDictionary as String] = tiff
    let bytes = try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0)
    guard bytes.count <= maximumPacketBytes else { throw CraftError.invalid("Stored image metadata exceeds its limit.") }
    source[RasterMetadata.propertiesKey] = bytes
    if fields.contains("copyrightStatus") || fields.contains("copyrightUrl"), let raw = source["psdResources"] {
      source["psdResources"] = try PSDImageResources.blocks(raw).filter {
        !(fields.contains("copyrightStatus") && $0.id == 1034) && !(fields.contains("copyrightUrl") && $0.id == 1035)
      }.reduce(into: Data()) { $0.append($1.raw) }
      if fields.contains("copyrightStatus"), info.copyrightStatus != .unknown {
        source["psdResources"]?.append(PSDImageResources.block(1034, data: Data([info.copyrightStatus == .copyrighted ? 1 : 0])))
      }
    }
    result.sourceMetadata = source; try result.validate(); return result
  }
}
