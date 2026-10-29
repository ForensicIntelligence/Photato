import Foundation
import ImageIO
import PhotoCraftCore

/// Update descriptive copyright fields while retaining unrelated camera/XMP data.
public enum CopyrightMetadata {
  public static func applying(_ text: String,to document: CraftDocument) throws -> CraftDocument {
    guard text.utf8.count <= 4096,!text.contains("\0") else {throw CraftError.invalid("Copyright text must be at most4096 UTF-8 bytes without null characters.")}
    var result = document,source = document.sourceMetadata ?? [:]
    var properties: [String:Any] = [:]
    if let bytes = source[RasterMetadata.propertiesKey] {
      guard bytes.count <= RasterMetadata.maximumBytes,let value = try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as? [String:Any] else {throw CraftError.invalid("Invalid stored image metadata.")};properties = value
    }
    var tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String:Any] ?? [:]
    var iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String:Any] ?? [:]
    tiff[kCGImagePropertyTIFFCopyright as String] = text;iptc[kCGImagePropertyIPTCCopyrightNotice as String] = text
    properties[kCGImagePropertyTIFFDictionary as String] = tiff;properties[kCGImagePropertyIPTCDictionary as String] = iptc
    let metadata: CGMutableImageMetadata
    if let data = try RasterMetadata.xmpData(source) {
      guard let original = CGImageMetadataCreateFromXMPData(data as CFData),let copy = CGImageMetadataCreateMutableCopy(original) else {throw CraftError.invalid("Invalid stored copyright/XMP metadata.")};metadata = copy
    } else {metadata = CGImageMetadataCreateMutable()}
    // Copyright is localized XMP text. Assign its default-language item: assigning
    // a scalar to the whole rights array can succeed but serialize an empty array.
    guard CGImageMetadataSetValueWithPath(metadata,nil,"dc:rights[x-default]" as CFString,text as CFString),let xmp = CGImageMetadataCreateXMPData(metadata,nil) as Data? else {throw CraftError.invalid("Could not update copyright metadata.")}
    source[RasterMetadata.propertiesKey] = try PropertyListSerialization.data(fromPropertyList:properties,format:.binary,options:0)
    source[RasterMetadata.xmpKey] = xmp
    result.sourceMetadata = source;try result.validate();return result
  }
}
