import Foundation
import PhotoCraftCore

/// PhotoCraft io/adjust_map.rs clrL mapping. Abstract/device-link ICC stays explicit.
enum PSDColorLookup {
  static func read(_ data: Data) throws -> ColorLookupAdjustment {
    var r = PSDReader(data:data)
    guard try r.u16() == 1 else { throw CraftError.invalid("Unsupported Color Lookup version.") }
    let d = try PSDDescriptor.read(r.bytes(r.remaining),padding:true)
    func enumeration(_ key: String, _ type: String, _ expected: String) throws {
      guard case .enumerated(let t,let v) = d[key], t.text == type, v.text == expected else { throw CraftError.unsupported("Unsupported Color Lookup \(key).") }
    }
    try enumeration("lookupType","colorLookupType","3DLUT")
    try enumeration("dataOrder","colorLookupOrder","rgbOrder")
    try enumeration("tableOrder","colorLookupOrder","bgrOrder")
    if let profile = d["profile"] {
      guard case .raw(let bytes) = profile, bytes.isEmpty else { throw CraftError.unsupported("ICC Color Lookup is unsupported.") }
    }
    guard case .raw(let bytes) = d["LUT3DFileData"], case .enumerated(let type,let format) = d["LUTFormat"], type.text == "LUTFormatType",
      let ext = ["LUTFormatCUBE":"cube","LUTFormat3DL":"3dl","LUTFormatLOOK":"look"][format.text] else { throw CraftError.unsupported("Unsupported Color Lookup format or data.") }
    let dither: Bool
    if let flag = d["Dthr"] {
      guard case .boolean(let value) = flag else { throw CraftError.invalid("Invalid LUT dither flag.") }; dither = value
    } else { dither = false }
    var name = "Color Lookup"
    if case .text(let filename) = d["LUT3DFileName"] ?? d["NM  "] {
      name = String(decoding:filename,as:UTF16.self).trimmingCharacters(in:CharacterSet(charactersIn:"\0"))
    }
    // The format descriptor is authoritative; source PhotoCraft may store a display name without an extension.
    if URL(fileURLWithPath:name).pathExtension.lowercased() != ext { name += "."+ext }
    return .init(lut:try ColorLUTFile.read(bytes,name:name),dither:dither)
  }
  static func write(_ value: ColorLookupAdjustment, original: Data? = nil) throws -> Data {
    try value.validate()
    guard value.interpolation == .trilinear, let lut = value.lut else { throw CraftError.unsupported("PSD Color Lookup requires a loaded LUT with Trilinear interpolation. Keep the Photato original for other settings.") }
    if let original, try read(original) == value { return original }
    let file = try ColorLUTFile.export(lut)
    let format = ["cube":"LUTFormatCUBE","3dl":"LUTFormat3DL","look":"LUTFormatLOOK"][URL(fileURLWithPath:file.name).pathExtension.lowercased()]!
    func e(_ type: String, _ value: String) -> PSDValue { .enumerated(.init(type),.init(value)) }
    let d = PSDDescriptor("null",items:[
      .init("lookupType",e("colorLookupType","3DLUT")),.init("NM  ",.text(Array(lut.title.utf16))),
      .init("Dthr",.boolean(value.dither)),.init("profile",.raw(Data())),
      .init("LUTFormat",e("LUTFormatType",format)),.init("dataOrder",e("colorLookupOrder","rgbOrder")),
      .init("tableOrder",e("colorLookupOrder","bgrOrder")),.init("LUT3DFileData",.raw(file.data)),.init("LUT3DFileName",.text(Array(file.name.utf16)))])
    var w = PSDWriter(); w.n(1,2); w.data.append(try d.encoded()); return w.data
  }
}
