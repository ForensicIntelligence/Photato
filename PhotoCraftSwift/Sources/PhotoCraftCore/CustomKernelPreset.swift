import Foundation

/// Public ACF Custom Kernel format: 25 row-major signed weights, Scale, Offset.
/// Photoshop-produced owned fixtures independently qualify the 54-byte layout.
public enum CustomKernelPreset {
  public enum Format:String,CaseIterable,Sendable {case acf,json}
  public static let maximumBytes=16_384
  public static let acfBytes=54

  public static func encode(_ settings:OtherVideoSettings,format:Format)throws->Data {
    try Task.checkCancellation()
    try settings.validate(kind:.customFilter)
    if format == .json {return try settings.encodedCustomPreset()}
    guard settings.scale.rounded()==settings.scale,settings.offset.rounded()==settings.offset else {
      throw CraftError.invalid("ACF requires whole-number Scale and Offset. Choose Photato JSON to preserve fractional values.")
    }
    var data=Data();data.reserveCapacity(acfBytes)
    for value in settings.kernel+[Int(settings.scale),Int(settings.offset)] {
      let bits=UInt16(bitPattern:Int16(value))
      data.append(UInt8(truncatingIfNeeded:bits>>8));data.append(UInt8(truncatingIfNeeded:bits))
    }
    return data
  }

  public static func decode(_ data:Data,format:Format)throws->OtherVideoSettings {
    try Task.checkCancellation()
    if format == .json {return try OtherVideoSettings.decodeCustomPreset(data)}
    guard data.count==acfBytes else {throw CraftError.invalid("An ACF Custom Kernel preset must contain exactly 54 bytes.")}
    // Copying 54 bytes also handles Data slices with a nonzero startIndex.
    let bytes=[UInt8](data)
    let values=(0..<27).map {i in Int(Int16(bitPattern:UInt16(bytes[2*i])<<8|UInt16(bytes[2*i+1])))}
    var settings=OtherVideoSettings();settings.kernel=Array(values.prefix(25))
    settings.scale=Double(values[25]);settings.offset=Double(values[26])
    try settings.validate(kind:.customFilter)
    return settings
  }

  /// Preserve JSON compatibility even when a valid JSON payload is 54 bytes long.
  public static func decode(_ data:Data)throws->OtherVideoSettings {
    let first=data.drop(while:{[UInt8(9),10,13,32].contains($0)}).first
    return try decode(data,format:first == 123 || data.count != acfBytes ? .json:.acf)
  }
}
