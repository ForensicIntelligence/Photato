import Foundation
import PhotoCraftCore
import zlib

/// Deterministic ZIP32 output for generated files, with UTF-8 names and CRC32.
/// PNG payloads are already compressed; no shell process or codec is invoked.
public enum StoredZIP {
  public struct File: Sendable {
    public let name: String
    public let data: Data
    public init(name: String, data: Data) { self.name = name; self.data = data }
  }
  public static func encode(_ files: [File], maximumBytes: Int, allowSubdirectories: Bool = false) throws -> Data {
    guard !files.isEmpty, files.count < 65_535, maximumBytes > 0, maximumBytes <= Int(UInt32.max), Set(files.map(\.name)).count == files.count else { throw CraftError.invalid("Invalid ZIP file count or output budget.") }
    var body = Data(), directory = Data()
    func put(_ value: Int, _ size: Int, into data: inout Data) { for i in 0..<size { data.append(UInt8((value >> (8*i)) & 255)) } }
    for file in files {
      try Task.checkCancellation()
      let name = Data(file.name.utf8)
      guard !name.isEmpty, name.count <= 65_535, safeName(file.name,allowSubdirectories:allowSubdirectories),
        file.data.count <= maximumBytes, body.count + directory.count + 98 + name.count*2 <= maximumBytes - file.data.count else { throw CraftError.invalid("Unsafe ZIP filename or output exceeds its byte budget.") }
      let offset = body.count, checksum = file.data.withUnsafeBytes { Int(crc32(0,$0.bindMemory(to:Bytef.self).baseAddress,uInt($0.count))) }
      for (n,size) in [(0x04034b50,4),(20,2),(0x800,2),(0,2),(0,2),(33,2),(checksum,4),(file.data.count,4),(file.data.count,4),(name.count,2),(0,2)] { put(n,size,into:&body) }
      body.append(name);body.append(file.data)
      for (n,size) in [(0x02014b50,4),(20,2),(20,2),(0x800,2),(0,2),(0,2),(33,2),(checksum,4),(file.data.count,4),(file.data.count,4),(name.count,2),(0,2),(0,2),(0,2),(0,2),(0,4),(offset,4)] { put(n,size,into:&directory) }
      directory.append(name)
    }
    let offset = body.count;body.append(directory)
    for (n,size) in [(0x06054b50,4),(0,2),(0,2),(files.count,2),(files.count,2),(directory.count,4),(offset,4),(0,2)] { put(n,size,into:&body) }
    try Task.checkCancellation();return body
  }
  private static func safeName(_ name: String,allowSubdirectories: Bool) -> Bool {
    guard !name.contains("\\"),!name.contains(":"),!name.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),allowSubdirectories || !name.contains("/") else {return false}
    let parts = name.split(separator:"/",omittingEmptySubsequences:false)
    return parts.allSatisfy{!$0.isEmpty && $0 != "." && $0 != ".."}
  }

}
