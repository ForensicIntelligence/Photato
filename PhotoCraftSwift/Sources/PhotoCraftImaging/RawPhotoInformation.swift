import Foundation
import ImageIO
import PhotoCraftCore
import UniformTypeIdentifiers

package struct RawPhotoInformation: Encodable, Equatable, Sendable {
  package let fileName: String
  package let type: String
  package let byteCount: Int
  package let width: Int
  package let height: Int
  package let camera: String
  package let lens: String?
  package let captureDate: String?
  package let captureOffset: String?
  package let caption: String?
  package let copyright: String?
  package let captureOrder: Date?

  init(fileName: String, byteCount: Int, sensor: RawSourceIO.Info, metadata: [String: Data]?, originalXMP: Data?) {
    let properties: [String: Any]
    if let packet = metadata?[RasterMetadata.propertiesKey],
      let decoded = try? PropertyListSerialization.propertyList(from: packet, format: nil) as? [String: Any] {
      properties = decoded
    } else { properties = [:] }
    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
    let xmp = (originalXMP ?? (try? RasterMetadata.xmpData(metadata))).flatMap { CGImageMetadataCreateFromXMPData($0 as CFData) }
    func nonempty(_ value: String?) -> String? {
      guard let value, !value.isEmpty else { return nil }
      return value
    }
    func field(_ path: String) -> String? {
      guard let xmp else { return nil }
      return nonempty(CGImageMetadataCopyStringValueWithPath(xmp, nil, path as CFString) as String?)
    }
    self.fileName = URL(fileURLWithPath: fileName).lastPathComponent
    type = sensor.type
    self.byteCount = byteCount
    width = sensor.nativeWidth
    height = sensor.nativeHeight
    camera = sensor.model
    lens = nonempty(exif[kCGImagePropertyExifLensModel as String] as? String) ?? field("aux:Lens")
    let exifDate = nonempty(exif[kCGImagePropertyExifDateTimeOriginal as String] as? String)
    // ImageIO maps XMP's exif:DateTimeOriginal to photoshop:DateCreated.
    let xmpDate = field("exif:DateTimeOriginal") ?? field("photoshop:DateCreated").flatMap { value in
      guard let exifDate else { return value }
      let date = value.prefix(10).replacingOccurrences(of: "-", with: ":")
      let time = value.dropFirst(11).prefix(8)
      return exifDate == "\(date) \(time)" ? value : nil
    }
    let exifOffset = nonempty(exif["OffsetTimeOriginal"] as? String)
    if exifOffset == nil, let xmpDate, Self.isoDate(xmpDate) != nil {
      // ImageIO can synthesize EXIF's wall time from XMP and omit its time zone.
      captureDate = xmpDate
      captureOffset = nil
    } else {
      captureDate = exifDate ?? xmpDate
      captureOffset = exifDate == nil ? nil : exifOffset
    }
    let info = try? FileInfoMetadata.readSource(metadata)
    caption = nonempty(info?.description)
    copyright = nonempty(info?.copyright)
    captureOrder = Self.sortDate(captureDate, offset: captureOffset)
  }

  package var formatTitle: String { UTType(type)?.localizedDescription ?? type }

  private static func isoDate(_ value: String) -> Date? {
    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: value) { return date }
    iso.formatOptions.insert(.withFractionalSeconds)
    return iso.date(from: value)
  }

  private static func sortDate(_ value: String?, offset: String?) -> Date? {
    guard let value else { return nil }
    if let date = isoDate(value) { return date }
    let exif = DateFormatter()
    exif.locale = Locale(identifier: "en_US_POSIX")
    exif.calendar = Calendar(identifier: .gregorian)
    exif.timeZone = TimeZone(secondsFromGMT: 0)
    exif.dateFormat = offset == nil ? "yyyy:MM:dd HH:mm:ss" : "yyyy:MM:dd HH:mm:ssXXXXX"
    return exif.date(from: value + (offset ?? ""))
  }

  private enum CodingKeys: String, CodingKey {
    case fileName, type, byteCount, width, height, camera, lens, captureDate, captureOffset, caption, copyright
  }
}
