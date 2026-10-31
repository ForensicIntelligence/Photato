import CryptoKit
import Foundation

struct NativeFlatIndexLimit:Error,LocalizedError { var errorDescription:String? { "Too many blobs for a legacy native archive; use version63." } }

/// Version11: a portable container with individually checked raster/selection
/// blobs and a binary-plist document manifest. File and Data output share this
/// serializer; only the file sink avoids retaining the complete output.
enum NativeChunkedArchive {
  static let magic = Data("PHOTATO\0".utf8)
  static let footerMagic = Data("PHTEND11".utf8)
  static let footerSize = 56
  static let header = magic + integer(11, width: 4) + integer(0, width: 4)
  struct Blob: Codable {
    var digest: String
    var offset: UInt64
    var length: UInt64
  }
  private enum Keys: String, CodingKey { case magic, version, document, blobs, recoveryContext }
  private struct EncodingEnvelope: Encodable {
    let document: CraftDocument
    let output: Output
    let recoveryContext: Data?
    let version: Int
    func encode(to encoder: any Encoder) throws {
      var c = encoder.container(keyedBy: Keys.self)
      try c.encode("PhotatoChunked", forKey: .magic)
      try c.encode(version, forKey: .version)
      try c.encode(document, forKey: .document)  // Appends blobs before the table is encoded.
      try c.encode(output.records, forKey: .blobs)
      try c.encodeIfPresent(recoveryContext, forKey: .recoveryContext)
    }
  }
  private struct Table: Decodable {
    var magic: String
    var version: Int
    var blobs: [Blob]
  }
  private struct DocumentEnvelope: Decodable { var document: CraftDocument }
  private struct RecoveryEnvelope: Decodable {
    let context: Data?
    let invalid: Bool
    init(from decoder: any Decoder) throws {
      let c = try decoder.container(keyedBy: Keys.self)
      guard c.contains(.recoveryContext) else { context = nil; invalid = false; return }
      if let data = try? c.decode(Data.self, forKey: .recoveryContext),
        data.count <= NativeArchive.maximumRecoveryContextBytes
      { context = data; invalid = false } else { context = nil; invalid = true }
    }
  }
  final class Output: RasterBlobEncoding, @unchecked Sendable {
    private let file: AtomicFileWriter?
    private let maximumBytes: Int
    private let recordLimit: Int
    private(set) var data = Data()
    private(set) var count = 0
    private var digests: Set<String> = []
    private(set) var records: [Blob] = []
    private(set) var reachedRecordLimit = false
    init(file: AtomicFileWriter? = nil, maximumBytes: Int, recordLimit: Int = 65_536) {
      self.file = file
      self.maximumBytes = maximumBytes
      self.recordLimit = recordLimit
    }
    func append(_ bytes: Data) throws {
      try Task.checkCancellation()
      guard bytes.count <= maximumBytes - count else {
        throw CraftError.invalid("Native archive exceeds the file size limit.")
      }
      if let file { try file.append(bytes) } else { data.append(bytes) }
      count += bytes.count
    }
    func storeBytes(_ data: Data) throws -> String {
      let digest = hexHash(data)
      if digests.contains(digest) { return digest }
      guard records.count < recordLimit else {
        reachedRecordLimit = true
        throw NativeFlatIndexLimit()
      }
      let record = Blob(digest: digest, offset: UInt64(count), length: UInt64(data.count))
      try append(data)
      records.append(record)
      digests.insert(digest)
      return digest
    }
  }
  final class InputContext: MappedRasterBlobDecoding, @unchecked Sendable {
    let records: [String: Blob]
    let read: (Int, Int) throws -> Data
    private var tiles: [String: [Pixel]] = [:]
    private var mappedTiles: [String: RasterTile] = [:]
    private let backing: RasterTileStore?
    var usesMappedTiles: Bool { backing != nil }
    private let decoder = TileArchive.Decoder()
    private(set) var used: Set<String> = []
    init(records: [String: Blob], backing: RasterTileStore? = nil, read: @escaping (Int, Int) throws -> Data) {
      self.records = records
      self.backing = backing
      self.read = read
    }
    func storedTile(_ digest: String) throws -> RasterTile {
      guard let backing else { return RasterTile(try tile(digest)) }
      if let tile = mappedTiles[digest] { return tile }
      let tile = try backing.append(RasterTile(try decoder.decode(bytes(digest, maximumBytes: TileArchive.byteCount + 1))))
      mappedTiles[digest] = tile
      return tile
    }
    func bytes(_ digest: String, maximumBytes: Int) throws -> Data {
      guard let blob = records[digest], blob.length <= UInt64(maximumBytes) else {
        throw CraftError.invalid("Missing or oversized native archive blob.")
      }
      let data = try read(Int(blob.offset), Int(blob.length))
      guard data.count == Int(blob.length), hexHash(data) == digest else {
        throw CraftError.invalid("Native archive integrity check failed.")
      }
      used.insert(digest)
      return data
    }
    func tile(_ digest: String) throws -> [Pixel] {
      if let value = tiles[digest] { return value }
      let pixels = try decoder.decode(bytes(digest, maximumBytes: TileArchive.byteCount + 1))
      tiles[digest] = pixels
      return pixels
    }
  }
  static func write(_ document: CraftDocument, output: Output, recoveryContext: Data? = nil, minimumVersion: Int = 11) throws {
    guard document.minimumArchiveVersion<63 else {throw CraftError.invalid("This document requires indexed native output.")}
    guard [11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62].contains(minimumVersion) else { throw CraftError.invalid("Invalid native archive output version.") }
    guard (recoveryContext?.count ?? 0) <= NativeArchive.maximumRecoveryContextBytes else {
      throw CraftError.invalid("Recovery source information exceeds its size limit.")
    }
    try Task.checkCancellation()
    try document.validate()
    let version = UInt64(max(minimumVersion, document.minimumArchiveVersion))
    try output.append(magic + integer(version, width: 4) + integer(0, width: 4))
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    encoder.userInfo[.historyTileEncoder] = output
    let metadata = try encoder.encode(EncodingEnvelope(document: document, output: output, recoveryContext: recoveryContext, version: Int(version)))
    guard metadata.count <= NativeArchive.maximumBytes else {
      throw NativeArchiveMemoryLimit.metadata(requiredBytes:metadata.count,limitBytes:NativeArchive.maximumBytes)
    }
    let start = output.count
    try output.append(metadata)
    try output.append(
      (version >= 12 ? Data("PHTEND\(version)".utf8) : footerMagic) + integer(UInt64(start), width: 8) + integer(UInt64(metadata.count), width: 8)
        + Data(SHA256.hash(data: metadata)))
  }
  static func decode(count: Int, rasterByteLimit: Int, read: @escaping (Int, Int) throws -> Data)
    throws -> CraftDocument
  {
    try decodeRecovery(count: count, rasterByteLimit: rasterByteLimit, read: read).document
  }
  static func decodeRecovery(count: Int, rasterByteLimit: Int,
    maximumMetadataBytes: Int = NativeArchive.maximumBytes, backing: RasterTileStore? = nil,
    maximumFileBytes: Int = NativeArchive.maximumBytes,
    read: @escaping (Int, Int) throws -> Data)
    throws -> NativeArchive.RecoveryContents
  {
    try Task.checkCancellation()
    if count >= 16, NativeIndexedArchive.supportsHeader(try read(0,16)) {
      return try NativeIndexedArchive.decodeRecovery(count:count,rasterByteLimit:rasterByteLimit,maximumMetadataBytes:maximumMetadataBytes,backing:backing,maximumFileBytes:maximumFileBytes,read:read)
    }
    guard count >= header.count + footerSize, count <= maximumFileBytes,
      (0...NativeArchive.maximumFileBytes).contains(maximumFileBytes),
      (0...1_073_741_824).contains(rasterByteLimit)
    else { throw CraftError.invalid("Invalid native archive size or raster budget.") }
    let (metadata, offset) = try manifest(
      count: count, maximumMetadataBytes: maximumMetadataBytes, maximumFileBytes:maximumFileBytes, read: read)
    let decoder = PropertyListDecoder()
    let table = try decoder.decode(Table.self, from: metadata)
    guard table.magic == "PhotatoChunked", [11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62].contains(table.version), table.blobs.count <= 65_536 else {
      throw CraftError.invalid("Invalid native archive manifest.")
    }
    var expected = UInt64(header.count)
    var records: [String: Blob] = [:]
    for record in table.blobs {
      try Task.checkCancellation()
      guard record.digest.utf8.count == 64,
        record.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
        records[record.digest] == nil, record.offset == expected,
        record.length <= offset - expected
      else {
        throw CraftError.invalid("Overlapping, missing or invalid native archive blob range.")
      }
      records[record.digest] = record
      expected += record.length
    }
    guard expected == offset else { throw CraftError.invalid("Unindexed native archive bytes.") }
    let context = InputContext(records: records, backing: backing, read: read)
    decoder.userInfo[.historyTileDecoder] = context
    decoder.userInfo[.rasterDecodeBudget] = RasterDecodeBudget(bytes: rasterByteLimit)
    var document = try decoder.decode(DocumentEnvelope.self, from: metadata).document
    guard context.used == Set(records.keys) else {
      throw CraftError.invalid("Unreferenced native archive blobs.")
    }
    try document.restoreModeCaches()
    try document.validate()
    guard document.minimumArchiveVersion <= table.version else { throw CraftError.invalid("Archive version cannot represent its document features.") }
    try Task.checkCancellation()
    let recovery = try decoder.decode(RecoveryEnvelope.self, from: metadata)
    return .init(document: document, context: recovery.context, invalidContext: recovery.invalid)
  }
  static func recoveryContext(count: Int, read: (Int, Int) throws -> Data) throws -> Data? {
    let metadata = try manifest(count: count, read: read).0
    let recovery = try PropertyListDecoder().decode(RecoveryEnvelope.self, from: metadata)
    return recovery.invalid ? nil : recovery.context
  }
  static func recoveryMetadata(count: Int, maximumMetadataBytes: Int,
    read: (Int, Int) throws -> Data) throws -> NativeArchive.RecoveryMetadata
  {
    let metadata = try manifest(count: count, maximumMetadataBytes: maximumMetadataBytes, read: read).0
    struct Header: Decodable {
      struct Document: Decodable { let width: Int; let height: Int }
      let magic: String
      let version: Int
      let document: Document
    }
    let decoder = PropertyListDecoder()
    let header = try decoder.decode(Header.self, from: metadata)
    guard (header.magic == "PhotatoIndexed" && [63,64].contains(header.version)) || (header.magic == "PhotatoChunked" && [11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62].contains(header.version)) else {
      throw CraftError.invalid("Invalid native archive manifest.")
    }
    _ = try Surface(width: header.document.width, height: header.document.height)
    let recovery = try decoder.decode(RecoveryEnvelope.self, from: metadata)
    return .init(context: recovery.context, invalidContext: recovery.invalid,
      width: header.document.width, height: header.document.height, manifestBytes: metadata.count)
  }
  static func manifest(count: Int, maximumMetadataBytes: Int = NativeArchive.maximumBytes,
    maximumFileBytes: Int = NativeArchive.maximumBytes,
    read: (Int, Int) throws -> Data) throws -> (Data, UInt64)
  {
    guard count >= header.count + footerSize, count <= maximumFileBytes,
      (0...NativeArchive.maximumFileBytes).contains(maximumFileBytes),
      (0...NativeArchive.maximumBytes).contains(maximumMetadataBytes) else {
      throw CraftError.invalid("Invalid native archive size.")
    }
    let bytes = try read(0, header.count)
    if NativeIndexedArchive.supportsHeader(bytes) {
      return try NativeIndexedArchive.manifest(count:count,maximumMetadataBytes:maximumMetadataBytes,maximumFileBytes:maximumFileBytes,read:read)
    }
    let header12 = magic + integer(12, width: 4) + integer(0, width: 4)
    let header13 = magic + integer(13, width: 4) + integer(0, width: 4)
    let header14 = magic + integer(14, width: 4) + integer(0, width: 4)
    let header62 = magic + integer(62, width: 4) + integer(0, width: 4)
    let header61 = magic + integer(61, width: 4) + integer(0, width: 4)
    let header60 = magic + integer(60, width: 4) + integer(0, width: 4)
    let header59 = magic + integer(59, width: 4) + integer(0, width: 4)
    let header58 = magic + integer(58, width: 4) + integer(0, width: 4)
    let header57 = magic + integer(57, width: 4) + integer(0, width: 4)
    let header56 = magic + integer(56, width: 4) + integer(0, width: 4)
    let header55 = magic + integer(55, width: 4) + integer(0, width: 4)
    let header54 = magic + integer(54, width: 4) + integer(0, width: 4)
    let header53 = magic + integer(53, width: 4) + integer(0, width: 4)
    let header52 = magic + integer(52, width: 4) + integer(0, width: 4)
    let header51 = magic + integer(51, width: 4) + integer(0, width: 4)
    let header50 = magic + integer(50, width: 4) + integer(0, width: 4)
    let header49 = magic + integer(49, width: 4) + integer(0, width: 4)
    let header48 = magic + integer(48, width: 4) + integer(0, width: 4)
    let header47 = magic + integer(47, width: 4) + integer(0, width: 4)
    let header46 = magic + integer(46, width: 4) + integer(0, width: 4)
    let header45 = magic + integer(45, width: 4) + integer(0, width: 4)
    let header44 = magic + integer(44, width: 4) + integer(0, width: 4)
    let header43 = magic + integer(43, width: 4) + integer(0, width: 4)
    let header42 = magic + integer(42, width: 4) + integer(0, width: 4)
    let header41 = magic + integer(41, width: 4) + integer(0, width: 4)
    let header40 = magic + integer(40, width: 4) + integer(0, width: 4)
    let header39 = magic + integer(39, width: 4) + integer(0, width: 4)
    let header38 = magic + integer(38, width: 4) + integer(0, width: 4)
    let header37 = magic + integer(37, width: 4) + integer(0, width: 4)
    let header36 = magic + integer(36, width: 4) + integer(0, width: 4)
    let header35 = magic + integer(35, width: 4) + integer(0, width: 4)
    let header34 = magic + integer(34, width: 4) + integer(0, width: 4)
    let header33 = magic + integer(33, width: 4) + integer(0, width: 4)
    let header32 = magic + integer(32, width: 4) + integer(0, width: 4)
    let header31 = magic + integer(31, width: 4) + integer(0, width: 4)
    let header30 = magic + integer(30, width: 4) + integer(0, width: 4)
    let header29 = magic + integer(29, width: 4) + integer(0, width: 4)
    let header28 = magic + integer(28, width: 4) + integer(0, width: 4)
    let header27 = magic + integer(27, width: 4) + integer(0, width: 4)
    let header26 = magic + integer(26, width: 4) + integer(0, width: 4)
    let header25 = magic + integer(25, width: 4) + integer(0, width: 4)
    let header24 = magic + integer(24, width: 4) + integer(0, width: 4)
    let header23 = magic + integer(23, width: 4) + integer(0, width: 4)
    let header22 = magic + integer(22, width: 4) + integer(0, width: 4)
    let header21 = magic + integer(21, width: 4) + integer(0, width: 4)
    let header20 = magic + integer(20, width: 4) + integer(0, width: 4)
    let header19 = magic + integer(19, width: 4) + integer(0, width: 4)
    let header18 = magic + integer(18, width: 4) + integer(0, width: 4)
    let header17 = magic + integer(17, width: 4) + integer(0, width: 4)
    let header16 = magic + integer(16, width: 4) + integer(0, width: 4)
    let header15 = magic + integer(15, width: 4) + integer(0, width: 4)
    let version = bytes == header62 ? 62 : bytes == header61 ? 61 : bytes == header60 ? 60 : bytes == header59 ? 59 : bytes == header58 ? 58 : bytes == header57 ? 57 : bytes == header56 ? 56 : bytes == header55 ? 55 : bytes == header54 ? 54 : bytes == header53 ? 53 : bytes == header52 ? 52 : bytes == header51 ? 51 : bytes == header50 ? 50 : bytes == header49 ? 49 : bytes == header48 ? 48 : bytes == header47 ? 47 : bytes == header46 ? 46 : bytes == header45 ? 45 : bytes == header44 ? 44 : bytes == header43 ? 43 : bytes == header42 ? 42 : bytes == header41 ? 41 : bytes == header40 ? 40 : bytes == header39 ? 39 : bytes == header38 ? 38 : bytes == header37 ? 37 : bytes == header36 ? 36 : bytes == header35 ? 35 : bytes == header34 ? 34 : bytes == header33 ? 33 : bytes == header32 ? 32 : bytes == header31 ? 31 : bytes == header30 ? 30 : bytes == header29 ? 29 : bytes == header28 ? 28 : bytes == header27 ? 27 : bytes == header26 ? 26 : bytes == header25 ? 25 : bytes == header24 ? 24 : bytes == header23 ? 23 : bytes == header22 ? 22 : bytes == header21 ? 21 : bytes == header20 ? 20 : bytes == header19 ? 19 : bytes == header18 ? 18 : bytes == header17 ? 17 : bytes == header16 ? 16 : bytes == header15 ? 15 : bytes == header14 ? 14 : bytes == header13 ? 13 : bytes == header12 ? 12 : 11
    guard bytes == header62 || bytes == header || bytes == header12 || bytes == header13 || bytes == header14 || bytes == header15 || bytes == header16 || bytes == header17 || bytes == header18 || bytes == header19 || bytes == header20 || bytes == header21 || bytes == header22 || bytes == header23 || bytes == header24 || bytes == header25 || bytes == header26 || bytes == header27 || bytes == header28 || bytes == header29 || bytes == header30 || bytes == header31 || bytes == header32 || bytes == header33 || bytes == header34 || bytes == header35 || bytes == header36 || bytes == header37 || bytes == header38 || bytes == header39 || bytes == header40 || bytes == header41 || bytes == header42 || bytes == header43 || bytes == header44 || bytes == header45 || bytes == header46 || bytes == header47 || bytes == header48 || bytes == header49 || bytes == header50 || bytes == header51 || bytes == header52 || bytes == header53 || bytes == header54 || bytes == header55 || bytes == header56 || bytes == header57 || bytes == header58 || bytes == header59 || bytes == header60 || bytes == header61 else {
      throw CraftError.unsupported("Unsupported chunked Photato archive version.")
    }
    let footer = try read(count - footerSize, footerSize)
    guard footer.starts(with: version >= 12 ? Data("PHTEND\(version)".utf8) : footerMagic) else {
      throw CraftError.invalid("Missing native archive footer.")
    }
    let offset = number(footer, at: 8)
    let length = number(footer, at: 16)
    guard offset >= UInt64(header.count), offset <= UInt64(count - footerSize),
      length == UInt64(count - footerSize) - offset
    else { throw CraftError.invalid("Invalid native archive manifest range.") }
    guard length <= UInt64(maximumMetadataBytes) else {
      throw NativeArchiveMemoryLimit.metadata(
        requiredBytes: Int(length), limitBytes: maximumMetadataBytes)
    }
    let metadata = try read(Int(offset), Int(length))
    guard Data(SHA256.hash(data: metadata)) == footer.suffix(32) else {
      throw CraftError.invalid("Native archive manifest integrity check failed.")
    }
    struct Version: Decodable { let version: Int }
    guard try PropertyListDecoder().decode(Version.self, from: metadata).version == version else {
      throw CraftError.invalid("Native archive header and manifest versions differ.")
    }
    return (metadata, offset)
  }
  static func integer(_ value: UInt64, width: Int) -> Data {
    Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
  }
  static func number(_ data: Data, at offset: Int) -> UInt64 {
    data.withUnsafeBytes {
      UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }
  }
  static func hexHash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

extension NativeArchive {
  /// In-memory containers and metadata retain their original independent bound.
  public static let maximumBytes = 512 * 1024 * 1024
  /// File transactions stream bounded chunks. Index/heap/scratch/metadata budgets
  /// remain separate; this admission ceiling does not prove dense4TiB capacity.
  public static let maximumFileBytes = 4_398_046_511_104
  public static let maximumRecoveryContextBytes = 128 * 1024
  public struct RecoveryContents: Sendable {
    public let document: CraftDocument
    public let context: Data?
    public let invalidContext: Bool
  }
  public struct RecoveryMetadata: Sendable {
    public let context: Data?
    public let invalidContext: Bool
    public let width: Int
    public let height: Int
    public let manifestBytes: Int
  }
  /// Recovery-only opaque metadata shares the manifest integrity check and publication.
  /// Normal document saves and downloads omit it, including when saving a recovered model.
  public static func writeRecovery(_ document: CraftDocument, context: Data?, to url: URL) throws {
    try write(document, to: url, maximumBytes: NativeArchive.maximumBytes, recoveryContext: context) {
      try AtomicFileWriter(to: $0, maximumBytes: $1)
    }
  }
  /// Legacy binary-plist encode(_:) remains available for existing integrations.
  /// New native document workflows use this portable version11 representation.
  public static func encodeChunked(
    _ document: CraftDocument, maximumBytes: Int = NativeArchive.maximumBytes, minimumVersion: Int = 11
  ) throws -> Data {
    guard (0...Self.maximumBytes).contains(maximumBytes) else {
      throw CraftError.invalid("Invalid native archive output limit.")
    }
    let output = NativeChunkedArchive.Output(maximumBytes: maximumBytes)
    if minimumVersion >= 63 || document.minimumArchiveVersion >= 64 { try NativeIndexedArchive.write(document,output:output,minimumVersion:max(63,minimumVersion)) }
    else { try NativeChunkedArchive.write(document, output: output, minimumVersion: minimumVersion) }
    return output.data
  }
  public static func write(
    _ document: CraftDocument, to url: URL, maximumBytes: Int = NativeArchive.maximumFileBytes
  ) throws {
    try write(document, to: url, maximumBytes: maximumBytes) {
      try AtomicFileWriter(to: $0, maximumBytes: $1)
    }
  }
  static func write(
    _ document: CraftDocument, to url: URL, maximumBytes: Int = NativeArchive.maximumFileBytes,
    recoveryContext: Data? = nil, legacyRecordLimit: Int = 65_536, makeFile: (URL, Int) throws -> AtomicFileWriter
  ) throws {
    guard (0...Self.maximumFileBytes).contains(maximumBytes), (0...65_536).contains(legacyRecordLimit) else {
      throw CraftError.invalid("Invalid native archive output limit.")
    }
    let file = try makeFile(url, maximumBytes)
    defer { file.discard() }
    let output = NativeChunkedArchive.Output(file:file,maximumBytes:maximumBytes,recordLimit:legacyRecordLimit)
    if document.mappedRasterIndexBytes>0 || document.minimumArchiveVersion>=64 {
      try NativeIndexedArchive.write(document,output:output,recoveryContext:recoveryContext)
      try file.commit();return
    }
    do {
      try NativeChunkedArchive.write(document, output:output, recoveryContext:recoveryContext)
      try file.commit()
    } catch {
      // PropertyListEncoder wraps errors from nested Codable values. The owned
      // output records this exact admission failure; other errors never retry.
      guard output.reachedRecordLimit else { throw error }
      // Older small-document output remains byte-compatible. Retry the atomic
      // transaction with the hierarchical format only when the flat table fills.
      file.discard()
      let indexed = try makeFile(url,maximumBytes); defer { indexed.discard() }
      try NativeIndexedArchive.write(document,output:.init(file:indexed,maximumBytes:maximumBytes),recoveryContext:recoveryContext)
      try indexed.commit()
    }
  }
  /// Inspect dimensions without inflating any tile; upload limits are enforced first.
  public static func dimensions(_ data: Data) throws -> (width: Int, height: Int) {
    guard data.count <= maximumBytes else {
      throw CraftError.invalid("Archive exceeds the input limit.")
    }
    struct Header: Decodable {
      struct Document: Decodable {
        let width: Int
        let height: Int
      }
      let document: Document
    }
    let metadata: Data
    if data.starts(with: NativeChunkedArchive.magic) {
      metadata = try NativeChunkedArchive.manifest(count: data.count) { offset, count in
        let start = data.startIndex + offset
        return data.subdata(in: start..<start + count)
      }.0
    } else {
      metadata = data
    }
    let header = try PropertyListDecoder().decode(Header.self, from: metadata)
    return (header.document.width, header.document.height)
  }
  public static func read(_ url: URL, rasterByteLimit: Int = 1_073_741_824) throws -> CraftDocument
  {
    try readRecovery(url, rasterByteLimit: rasterByteLimit).document
  }
  /// Inspect checked recovery metadata without decoding image tiles. Callers must
  /// still validate the full archive and recheck its context before adopting it.
  public static func readRecoveryContext(_ url: URL) throws -> Data? {
    try NativeArchiveFileSource.withStableMetadata {
      let source = try NativeArchiveFileSource(url)
      guard try source.read(at: 0, count: min(source.count, NativeChunkedArchive.magic.count))
        == NativeChunkedArchive.magic else { return nil }
      let context = try NativeChunkedArchive.recoveryContext(count: source.count) {
        try source.read(at: $0, count: $1)
      }
      try source.validateUnchanged()
      return context
    }
  }
  /// Native11 recovery metadata without raster/blob decoding. The manifest range
  /// is checked against the caller's allowance before allocating its read buffer.
  public static func readRecoveryMetadata(_ url: URL,
    maximumMetadataBytes: Int = NativeArchive.maximumBytes) throws -> RecoveryMetadata?
  {
    try NativeArchiveFileSource.withStableMetadata {
      let source = try NativeArchiveFileSource(url)
      guard try source.read(at: 0, count: min(source.count, NativeChunkedArchive.magic.count))
        == NativeChunkedArchive.magic else { return nil }
      let result = try NativeChunkedArchive.recoveryMetadata(
        count: source.count, maximumMetadataBytes: maximumMetadataBytes) {
          try source.read(at: $0, count: $1)
        }
      try source.validateUnchanged()
      return result
    }
  }
  public static func readRecovery(_ url: URL, rasterByteLimit: Int = 1_073_741_824,
    maximumMetadataBytes: Int = NativeArchive.maximumBytes) throws
    -> RecoveryContents
  {
    try NativeArchiveFileSource.withStableMetadata {
      try readOnce(url, rasterByteLimit: rasterByteLimit, maximumMetadataBytes: maximumMetadataBytes)
    }
  }
  private static func readOnce(_ url: URL, rasterByteLimit: Int,
    maximumMetadataBytes: Int) throws -> RecoveryContents {
    guard (0...maximumBytes).contains(maximumMetadataBytes) else {
      throw CraftError.invalid("Invalid native metadata read budget.")
    }
    let source = try NativeArchiveFileSource(url)
    let result: RecoveryContents
    if try source.read(at: 0, count: min(source.count, NativeChunkedArchive.magic.count))
      == NativeChunkedArchive.magic
    {
      result = try NativeChunkedArchive.decodeRecovery(
        count: source.count, rasterByteLimit: rasterByteLimit, maximumMetadataBytes: maximumMetadataBytes
      ) { try source.read(at: $0, count: $1) }
    } else {
      guard source.count <= maximumMetadataBytes else {
        throw NativeArchiveMemoryLimit.metadata(
          requiredBytes: source.count, limitBytes: maximumMetadataBytes)
      }
      // Preserve mapped legacy loading until portable legacy-file streaming exists.
      result = .init(document: try decode(
        Data(contentsOf: url, options: .mappedIfSafe), rasterByteLimit: rasterByteLimit),
        context: nil, invalidContext: false)
    }
    try source.validateUnchanged()
    return result
  }
}
