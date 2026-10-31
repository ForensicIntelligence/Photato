import CryptoKit
import Foundation

/// Version63 appends a bounded, authenticated B-tree after variable-size payloads.
/// It preserves older document feature versions and never accepts external paths.
enum NativeIndexedArchive {
  static let header = NativeChunkedArchive.magic + NativeChunkedArchive.integer(63,width:4) + NativeChunkedArchive.integer(0,width:4)
  static let footer = Data("PHTEND63".utf8)
  static func containerHeader(_ version:Int)->Data {NativeChunkedArchive.magic+NativeChunkedArchive.integer(UInt64(version),width:4)+NativeChunkedArchive.integer(0,width:4)}
  static func containerFooter(_ version:Int)->Data {Data("PHTEND\(version)".utf8)}
  static func supportsHeader(_ bytes:Data)->Bool {bytes==header || bytes==containerHeader(64)}
  static func identifier(_ ordinal:UInt64)->String { "b\(ordinal)" }
  private enum Keys:String,CodingKey {case magic,version,document,index,recoveryContext}
  private struct Envelope:Encodable {
    let document:CraftDocument;let output:Output;let context:Data?;let version:Int
    func encode(to encoder:any Encoder)throws {
      var c=encoder.container(keyedBy:Keys.self)
      try c.encode("PhotatoIndexed",forKey:.magic);try c.encode(version,forKey:.version)
      try c.encode(document,forKey:.document)
      try c.encode(output.finishIndex(),forKey:.index)
      try c.encodeIfPresent(context,forKey:.recoveryContext)
    }
  }
  private struct Table:Decodable {let magic:String;let version:Int;let index:NativeBlobIndex.Catalog}
  private struct DocumentEnvelope:Decodable {let document:CraftDocument}
  private struct Recovery:Decodable {
    let context:Data?;let invalid:Bool
    init(from decoder:any Decoder)throws {
      let c=try decoder.container(keyedBy:Keys.self)
      guard c.contains(.recoveryContext) else {context=nil;invalid=false;return}
      if let value=try? c.decode(Data.self,forKey:.recoveryContext),value.count<=NativeArchive.maximumRecoveryContextBytes {context=value;invalid=false}
      else {context=nil;invalid=true}
    }
  }
  final class Output:IndexedRasterBlobEncoding,@unchecked Sendable {
    let sink:NativeChunkedArchive.Output
    private let scratch:NativeIndexScratch
    private let index:NativeBlobIndex.Writer
    private var cache:[Data:UInt64]=[:],order:[Data]=[]
    init(sink:NativeChunkedArchive.Output)throws {
      self.sink=sink;let scratch=try NativeIndexScratch();self.scratch=scratch
      index=NativeBlobIndex.Writer(appendNode:scratch.append)
    }
    func storeBytes(_ data:Data)throws->String {NativeIndexedArchive.identifier(try storeOrdinal(data))}
    func storeOrdinal(_ data:Data)throws->UInt64 {
      try Task.checkCancellation()
      let digest=Data(SHA256.hash(data:data))
      if let ordinal=cache[digest] {return ordinal}
      let offset=sink.count;try sink.append(data)
      let ordinal=try index.append(.init(offset:UInt64(offset),length:UInt64(data.count),digest:digest))
      if cache.count==1024 {cache.removeValue(forKey:order.removeFirst())}
      cache[digest]=ordinal;order.append(digest);return ordinal
    }
    func finishIndex()throws->NativeBlobIndex.Catalog {
      let catalog=try index.finish();var at=0
      while at<scratch.count {try Task.checkCancellation();let n=min(65536,scratch.count-at);try sink.append(scratch.read(UInt64(at),n));at+=n}
      return catalog
    }
  }
  final class Input:IndexedRasterBlobDecoding,@unchecked Sendable {
    private let index:NativeBlobIndex.Reader
    private let read:(Int,Int)throws->Data
    private let backing:RasterTileStore?
    private let decoder=TileArchive.Decoder()
    private var used:Data,usedCount:UInt64=0
    private let mappedCache:NativeMappedTileCache?
    private var cache:[UInt64:RasterTile]=[:],order:[UInt64]=[]
    var usesMappedTiles:Bool {backing != nil}
    init(index:NativeBlobIndex.Reader,backing:RasterTileStore?,budget:RasterDecodeBudget,read:@escaping(Int,Int)throws->Data)throws {
      self.index=index;self.backing=backing;self.read=read
      let n=index.catalog.records/8 + (index.catalog.records%8 == 0 ? 0:1)
      guard n<=UInt64(Int.max) else {throw CraftError.invalid("Native index use map size.")}
      try budget.reserve(bytes:Int(n));used=Data(count:Int(n))
      if backing != nil {
        try budget.reserve(bytes:NativeMappedTileCache.baseResidentEstimate)
        mappedCache=try NativeMappedTileCache(records:index.catalog.records,reserveSegment:{try budget.reserve(bytes:$0)})
      } else {mappedCache=nil}
    }
    var allReferenced:Bool {usedCount==index.catalog.records}
    func bytes(_ identifier:String,maximumBytes:Int)throws->Data {
      try Task.checkCancellation()
      guard identifier.first=="b",let ordinal=UInt64(identifier.dropFirst()),identifier==NativeIndexedArchive.identifier(ordinal),maximumBytes>=0 else {throw CraftError.invalid("Invalid native blob ordinal.")}
      let record=try index.record(at:ordinal)
      guard record.length<=UInt64(maximumBytes) else {throw CraftError.invalid("Oversized native blob.")}
      let data=try read(Int(record.offset),Int(record.length))
      guard data.count==Int(record.length),Data(SHA256.hash(data:data))==record.digest else {throw CraftError.invalid("Native blob integrity check failed.")}
      let byte=Int(ordinal/8),mask:UInt8=1<<UInt8(ordinal%8)
      if used[byte]&mask==0 {used[byte] |= mask;usedCount+=1}
      return data
    }
    func storedTile(_ identifier:String)throws->RasterTile {
      try Task.checkCancellation()
      guard identifier.first=="b",let ordinal=UInt64(identifier.dropFirst()),identifier==NativeIndexedArchive.identifier(ordinal) else {throw CraftError.invalid("Invalid native tile ordinal.")}
      if let value=cache[ordinal] {return value}
      if let value=try mappedCache?.tile(at:ordinal) {return value}
      let tile=RasterTile(try decoder.decode(bytes(identifier,maximumBytes:TileArchive.byteCount+1)))
      let stored=try backing?.append(tile) ?? tile
      try mappedCache?.store(stored,at:ordinal)
      if cache.count==NativeArchive.indexedTileCacheFrontEntries {cache.removeValue(forKey:order.removeFirst())}
      cache[ordinal]=stored;order.append(ordinal);return stored
    }
    func tile(_ identifier:String)throws->[Pixel] {Array(try storedTile(identifier))}
  }
  static func write(_ document:CraftDocument,output:NativeChunkedArchive.Output,recoveryContext:Data?=nil,minimumVersion:Int=63)throws {
    try Task.checkCancellation();try document.validate()
    guard (recoveryContext?.count ?? 0)<=NativeArchive.maximumRecoveryContextBytes else {throw CraftError.invalid("Recovery context exceeds its limit.")}
    guard [63,64].contains(minimumVersion) else {throw CraftError.invalid("Invalid indexed native output version.")}
    let version=max(minimumVersion,document.minimumArchiveVersion)
    guard [63,64].contains(version) else {throw CraftError.invalid("Unsupported indexed document features.")}
    try output.append(containerHeader(version))
    let context=try Output(sink:output),encoder=PropertyListEncoder();encoder.outputFormat = .binary
    encoder.userInfo[.historyTileEncoder]=context
    let metadata=try encoder.encode(Envelope(document:document,output:context,context:recoveryContext,version:version))
    guard metadata.count<=NativeArchive.maximumBytes else {throw NativeArchiveMemoryLimit.metadata(requiredBytes:metadata.count,limitBytes:NativeArchive.maximumBytes)}
    let offset=output.count;try output.append(metadata)
    try output.append(containerFooter(version)+NativeChunkedArchive.integer(UInt64(offset),width:8)+NativeChunkedArchive.integer(UInt64(metadata.count),width:8)+Data(SHA256.hash(data:metadata)))
  }
  static func manifest(count:Int,maximumMetadataBytes:Int,maximumFileBytes:Int,read:(Int,Int)throws->Data)throws->(Data,UInt64) {
    guard count>=72,count<=maximumFileBytes,(0...NativeArchive.maximumFileBytes).contains(maximumFileBytes),(0...NativeArchive.maximumBytes).contains(maximumMetadataBytes),supportsHeader(try read(0,16)) else {throw CraftError.invalid("Invalid indexed native archive size/header.")}
    let version=Int(NativeChunkedArchive.number(try read(0,16),at:8))
    let end=try read(count-56,56)
    guard end.count==56,end.starts(with:containerFooter(version)) else {throw CraftError.invalid("Missing indexed native footer.")}
    let offset=NativeChunkedArchive.number(end,at:8),length=NativeChunkedArchive.number(end,at:16)
    guard offset>=16,offset<=UInt64(count-56),length==UInt64(count-56)-offset else {throw CraftError.invalid("Invalid indexed native manifest range.")}
    guard length<=UInt64(maximumMetadataBytes) else {throw NativeArchiveMemoryLimit.metadata(requiredBytes:Int(length),limitBytes:maximumMetadataBytes)}
    let bytes=try read(Int(offset),Int(length))
    guard bytes.count==Int(length),Data(SHA256.hash(data:bytes))==end.suffix(32) else {throw CraftError.invalid("Indexed native manifest integrity check failed.")}
    let table=try PropertyListDecoder().decode(Table.self,from:bytes)
    guard table.magic=="PhotatoIndexed",table.version==version,table.index.payloadEnd>=16,table.index.payloadEnd<=offset,table.index.indexBytes==offset-table.index.payloadEnd else {throw CraftError.invalid("Invalid native index region.")}
    return(bytes,offset)
  }
  static func decodeRecovery(count:Int,rasterByteLimit:Int,maximumMetadataBytes:Int,backing:RasterTileStore?,maximumFileBytes:Int,read:@escaping(Int,Int)throws->Data)throws->NativeArchive.RecoveryContents {
    try Task.checkCancellation()
    guard (0...1_073_741_824).contains(rasterByteLimit) else {throw CraftError.invalid("Invalid indexed raster budget.")}
    let (bytes,_)=try manifest(count:count,maximumMetadataBytes:maximumMetadataBytes,maximumFileBytes:maximumFileBytes,read:read)
    let decoder=PropertyListDecoder(),table=try decoder.decode(Table.self,from:bytes),start=table.index.payloadEnd
    let index=try NativeBlobIndex.Reader(catalog:table.index) {offset,length in
      // Catalog bounds are validated before the read; absolute addition stays in the admitted file.
      guard offset<=table.index.indexBytes,UInt64(length)<=table.index.indexBytes-offset else {throw CraftError.invalid("Invalid native index read.")}
      return try read(Int(start+offset),length)
    }
    try index.validate()
    let budget=RasterDecodeBudget(bytes:rasterByteLimit)
    let context=try Input(index:index,backing:backing,budget:budget,read:read)
    decoder.userInfo[.historyTileDecoder]=context;decoder.userInfo[.rasterDecodeBudget]=budget
    var document=try decoder.decode(DocumentEnvelope.self,from:bytes).document
    guard context.allReferenced else {throw CraftError.invalid("Unreferenced indexed native blobs.")}
    try document.restoreModeCaches();try document.validate()
    guard document.minimumArchiveVersion<=table.version else {throw CraftError.invalid("Unsupported indexed document features.")}
    try Task.checkCancellation();let recovery=try decoder.decode(Recovery.self,from:bytes)
    return .init(document:document,context:recovery.context,invalidContext:recovery.invalid)
  }
}

/// At most1024 (tile-key, blob-ordinal) pairs in one checked payload.
enum NativeTilePage {
  static let capacity=1024,maximumBytes=12+1024*16
  private static let magic=Data("PHTTIL04".utf8)
  static func encode(_ entries:[(Int,UInt64)])throws->Data {
    guard !entries.isEmpty,entries.count<=capacity,entries.allSatisfy({$0.0>=0}) else {throw CraftError.invalid("Invalid native tile page.")}
    var data=magic+NativeChunkedArchive.integer(UInt64(entries.count),width:4)
    for (key,ordinal) in entries {data.append(NativeChunkedArchive.integer(UInt64(key),width:8));data.append(NativeChunkedArchive.integer(ordinal,width:8))}
    return data
  }
  static func decode(_ bytes:Data)throws->[(Int,UInt64)] {
    guard bytes.count>=12,bytes.count<=maximumBytes,bytes.starts(with:magic) else {throw CraftError.invalid("Invalid native tile page header.")}
    let count=bytes.withUnsafeBytes{Int(UInt32(littleEndian:$0.loadUnaligned(fromByteOffset:8,as:UInt32.self)))}
    guard count>0,count<=capacity,bytes.count==12+count*16 else {throw CraftError.invalid("Invalid native tile page length.")}
    var entries:[(Int,UInt64)]=[];entries.reserveCapacity(count)
    for i in 0..<count {let key=NativeChunkedArchive.number(bytes,at:12+i*16);guard key<=UInt64(Int.max) else {throw CraftError.invalid("Native tile key overflow.")};entries.append((Int(key),NativeChunkedArchive.number(bytes,at:20+i*16)))}
    return entries
  }
}
