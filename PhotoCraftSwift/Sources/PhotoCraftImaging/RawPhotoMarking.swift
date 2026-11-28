import Foundation
import ImageIO
import PhotoCraftCore

/// XMP Basic properties shared by Camera Raw and other photography software.
package struct RawPhotoMarking: Equatable, Sendable {
  private static let namespace = "http://ns.adobe.com/xap/1.0/"
  package var rating: Int?
  /// An empty label explicitly clears an inherited label.
  package var label: String?

  package init(rating: Int? = nil, label: String? = nil) {
    self.rating = rating
    self.label = label
  }

  package var isEmpty: Bool { rating == nil && label == nil }

  package func overlay(_ newer: Self) -> Self {
    Self(rating: newer.rating ?? rating, label: newer.label ?? label)
  }

  static func read(_ data: Data?) -> Self {
    guard let data, (1...FileInfoMetadata.maximumPacketBytes).contains(data.count) else { return .init() }
    let imageMetadata = CGImageMetadataCreateFromXMPData(data as CFData)
    let rating = imageMetadata.flatMap { string("Rating", in: $0) }.flatMap(Int.init)
    let label = imageMetadata.flatMap { string("Label", in: $0) }
    // ImageIO emits the standard empty XMP property, but omits it when reading
    // tags. Retain the distinction between absent and explicitly cleared.
    return .init(rating: rating.flatMap { (-1...5).contains($0) ? $0 : nil },
      label: label ?? (EmptyLabel.exists(in: data, namespace: namespace) ? "" : nil))
  }

  private static func tag(_ name: String, in metadata: CGImageMetadata) -> CGImageMetadataTag? {
    (CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag])?.first {
      CGImageMetadataTagCopyNamespace($0) as String? == namespace &&
        CGImageMetadataTagCopyName($0) as String? == name
    }
  }

  private static func string(_ name: String, in metadata: CGImageMetadata) -> String? {
    guard let tag = tag(name, in: metadata) else { return nil }
    let value = CGImageMetadataTagCopyValue(tag)
    return (value as? String) ?? (value as? NSNumber)?.stringValue
  }

  func write(into metadata: CGMutableImageMetadata) throws {
    func put(_ field: String, _ value: String?) throws {
      guard let value, value != Self.string(field, in: metadata) else { return }
      let existing = Self.tag(field, in: metadata) ?? Self.tag("Rating", in: metadata) ?? Self.tag("Label", in: metadata)
      let prefix = existing.flatMap { CGImageMetadataTagCopyPrefix($0) as String? } ?? "xmp"
      guard CGImageMetadataRegisterNamespaceForPrefix(metadata, Self.namespace as CFString, prefix as CFString, nil),
        let tag = CGImageMetadataTagCreate(Self.namespace as CFString, prefix as CFString,
          field as CFString, .string, value as CFString),
        CGImageMetadataSetTagWithPath(metadata, nil, "\(prefix):\(field)" as CFString, tag) else {
        throw CraftError.invalid("Could not write the RAW photo's \(field.lowercased()).")
      }
    }
    try put("Rating", rating.map(String.init))
    try put("Label", label)
  }

  package static func read(in document: CraftDocument) throws -> Self {
    read(try FileInfoMetadata.packet(document))
  }

  package func applying(to document: CraftDocument) throws -> CraftDocument {
    guard !isEmpty else { return document }
    let original = try FileInfoMetadata.packet(document)
    let previous = Self.read(original)
    guard previous.overlay(self) != previous else { return document }
    let metadata: CGMutableImageMetadata
    if let original {
      guard let parsed = CGImageMetadataCreateFromXMPData(original as CFData),
        let copy = CGImageMetadataCreateMutableCopy(parsed) else {
        throw CraftError.invalid("The photo’s existing XMP metadata cannot be updated.")
      }
      metadata = copy
    } else { metadata = CGImageMetadataCreateMutable() }
    if previous.label == "", label == nil { try Self(label: "").write(into: metadata) }
    try write(into: metadata)
    guard let packet = CGImageMetadataCreateXMPData(metadata, nil) as Data?,
      packet.count <= FileInfoMetadata.maximumPacketBytes else {
      throw CraftError.invalid("Could not encode the photo’s XMP metadata.")
    }
    var result = document
    var source = result.sourceMetadata ?? [:]
    source[RasterMetadata.xmpKey] = packet
    result.sourceMetadata = source
    return result
  }
}

private final class EmptyLabel: NSObject, XMLParserDelegate {
  private let namespace: String
  private var mappings: [String: [String]] = [:]
  private var depth = 0
  private var labelDepth: Int?
  private var hasContent = false
  private var found = false

  init(namespace: String) { self.namespace = namespace }

  static func exists(in data: Data, namespace: String) -> Bool {
    let delegate = EmptyLabel(namespace: namespace)
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = true
    parser.shouldReportNamespacePrefixes = true
    parser.shouldResolveExternalEntities = false
    parser.externalEntityResolvingPolicy = .never
    parser.delegate = delegate
    return parser.parse() && delegate.found
  }

  func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI uri: String) {
    mappings[prefix, default: []].append(uri)
  }

  func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
    if mappings[prefix]?.isEmpty == false { mappings[prefix]?.removeLast() }
  }

  func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
    qualifiedName: String?, attributes: [String: String]) {
    depth += 1
    if labelDepth != nil { hasContent = true }
    if namespaceURI == namespace && element == "Label" {
      labelDepth = depth
      hasContent = false
    }
    if attributes.contains(where: { key, value in
      let path = key.split(separator: ":", maxSplits: 1)
      return path.count == 2 && path[1] == "Label" && mappings[String(path[0])]?.last == namespace && value.isEmpty
    }) { found = true }
  }

  func parser(_ parser: XMLParser, foundCharacters string: String) {
    if labelDepth != nil && !string.isEmpty { hasContent = true }
  }

  func parser(_ parser: XMLParser, foundCDATA data: Data) {
    if labelDepth != nil && !data.isEmpty { hasContent = true }
  }

  func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
    if labelDepth == depth {
      found = found || !hasContent
      labelDepth = nil
    }
    depth -= 1
  }

  func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
    parser.abortParsing()
  }

  func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String,
    publicID: String?, systemID: String?) {
    parser.abortParsing()
  }
}
