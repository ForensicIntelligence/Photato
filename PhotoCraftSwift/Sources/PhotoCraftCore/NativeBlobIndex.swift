import CryptoKit
import Darwin
import Foundation

/// The persistent index is independent of raster sample encoding. Ordinals are
/// contiguous; payloads and postorder index subtrees must cover their regions
/// exactly. Readers retain a bounded node cache, never a whole record dictionary.
enum NativeIndexFailure: Error, LocalizedError, Equatable {
  case invalid(String)
  case capacity(required: Int, limit: Int)
  case io(String, Int32)
  var errorDescription: String? {
    switch self {
    case .invalid(let reason): "Invalid native index: \(reason)"
    case .capacity: "Native index scratch exceeds its admitted disk budget."
    case .io(let operation, let code): "Native index \(operation) failed: \(String(cString:strerror(code)))"
    }
  }
}

enum NativeBlobIndex {
  static let leafCapacity = 1024
  static let branchCapacity = 256
  static let maximumNodeBytes = 65_536
  static let maximumLevel = 16
  private static let magic = Data("PHTIDX01".utf8)
  struct Record: Equatable {
    let offset: UInt64
    let length: UInt64
    let digest: Data
  }
  struct Reference: Codable, Equatable {
    let offset: UInt64
    let length: Int
    let level: Int
    let first: UInt64
    let count: UInt64
    let spanStart: UInt64
    let spanEnd: UInt64
    let digest: Data
  }
  struct Catalog: Codable, Equatable {
    let root: Reference?
    let records: UInt64
    let indexBytes: UInt64
    let payloadEnd: UInt64
  }
  private enum Node { case leaf([Record]), branch([Reference]) }

  final class Writer {
    private let appendNode: (Data) throws -> UInt64
    private var leaf: [Record] = []
    private var levels: [[Reference]] = []
    private var first: UInt64 = 0
    private var count: UInt64 = 0
    private var indexBytes: UInt64 = 0
    private var payloadEnd: UInt64
    private var finished = false
    private var failed = false
    private(set) var maximumBufferedRecords = 0
    private(set) var maximumBufferedReferences = 0
    init(payloadStart: UInt64 = 16, appendNode: @escaping (Data) throws -> UInt64) {
      payloadEnd = payloadStart; self.appendNode = appendNode
    }
    @discardableResult func append(_ record: Record) throws -> UInt64 {
      guard !failed else { throw NativeIndexFailure.invalid("index writer failed") }
      do { return try appendRecord(record) } catch { failed = true; throw error }
    }
    private func appendRecord(_ record: Record) throws -> UInt64 {
      try Task.checkCancellation()
      guard !finished, record.digest.count == 32, record.offset == payloadEnd,
        record.length <= UInt64.max - payloadEnd, count < UInt64.max else {
        throw NativeIndexFailure.invalid("noncontiguous payload record")
      }
      let ordinal = count
      if leaf.isEmpty { first = count }
      leaf.append(record); maximumBufferedRecords = max(maximumBufferedRecords,leaf.count)
      count += 1; payloadEnd += record.length
      if leaf.count == leafCapacity { try flushLeaf() }
      return ordinal
    }
    func finish() throws -> Catalog {
      guard !failed else { throw NativeIndexFailure.invalid("index writer failed") }
      do { return try finishIndex() } catch { failed = true; throw error }
    }
    private func finishIndex() throws -> Catalog {
      try Task.checkCancellation()
      guard !finished else { throw NativeIndexFailure.invalid("index writer already finished") }
      if !leaf.isEmpty { try flushLeaf() }
      while let lowest = levels.firstIndex(where: { !$0.isEmpty }) {
        let higher = levels.indices.contains { $0 > lowest && !levels[$0].isEmpty }
        if levels[lowest].count == 1 && !higher {
          finished = true
          return Catalog(root:levels[lowest][0],records:count,indexBytes:indexBytes,payloadEnd:payloadEnd)
        }
        try flushLevel(lowest)
      }
      finished = true
      return Catalog(root:nil,records:0,indexBytes:0,payloadEnd:payloadEnd)
    }
    private func flushLeaf() throws {
      var data = header(level:0,entries:leaf.count,first:first,count:UInt64(leaf.count))
      for record in leaf { put(record.offset,into:&data);put(record.length,into:&data);data.append(record.digest) }
      let ref = try store(data,level:0,first:first,count:UInt64(leaf.count),spanStart:indexBytes)
      leaf.removeAll(keepingCapacity:true)
      try append(ref,to:0)
    }
    private func append(_ reference: Reference,to level: Int) throws {
      guard level <= maximumLevel else { throw NativeIndexFailure.invalid("index hierarchy is too deep") }
      while levels.count <= level { levels.append([]) }
      levels[level].append(reference)
      maximumBufferedReferences = max(maximumBufferedReferences,levels.reduce(0){$0+$1.count})
      if levels[level].count == branchCapacity { try flushLevel(level) }
    }
    private func flushLevel(_ level: Int) throws {
      let children = levels[level]
      guard !children.isEmpty,level < maximumLevel else { throw NativeIndexFailure.invalid("invalid hierarchy frontier") }
      let first = children[0].first,span = children[0].spanStart
      var next = first,end = span
      for child in children {
        guard child.level == level,child.first == next,child.spanStart == end,
          child.count <= UInt64.max-next else { throw NativeIndexFailure.invalid("noncontiguous child subtree") }
        next += child.count;end = child.spanEnd
      }
      guard end == indexBytes else { throw NativeIndexFailure.invalid("postorder index frontier") }
      var data = header(level:level+1,entries:children.count,first:first,count:next-first)
      for child in children { encode(child,into:&data) }
      let parent = try store(data,level:level+1,first:first,count:next-first,spanStart:span)
      levels[level].removeAll(keepingCapacity:true)
      try append(parent,to:level+1)
    }
    private func store(_ data:Data,level:Int,first:UInt64,count:UInt64,spanStart:UInt64)throws->Reference {
      try Task.checkCancellation()
      guard data.count <= maximumNodeBytes,UInt64(data.count) <= UInt64.max-indexBytes else { throw NativeIndexFailure.invalid("index node size") }
      let offset = try appendNode(data)
      guard offset == indexBytes else { throw NativeIndexFailure.invalid("noncontiguous index sink") }
      indexBytes += UInt64(data.count)
      return Reference(offset:offset,length:data.count,level:level,first:first,count:count,spanStart:spanStart,spanEnd:indexBytes,digest:Data(SHA256.hash(data:data)))
    }
  }

  final class Reader {
    let catalog:Catalog
    private let read:(UInt64,Int)throws->Data
    private let cacheLimit:Int
    private var cache:[UInt64:(Reference,Node)] = [:]
    private var order:[UInt64] = []
    private var checked = false
    private(set) var maximumCachedNodes = 0
    private(set) var nodeReads = 0
    init(catalog:Catalog,cacheNodes:Int = 8,read:@escaping(UInt64,Int)throws->Data)throws {
      guard (0...64).contains(cacheNodes) else { throw NativeIndexFailure.invalid("node cache allowance") }
      self.catalog=catalog;self.cacheLimit=cacheNodes;self.read=read
    }
    func validate(payloadStart:UInt64 = 16)throws {
      try Task.checkCancellation();checked=false
      if catalog.records == 0 {
        guard catalog.root == nil,catalog.indexBytes == 0,catalog.payloadEnd == payloadStart else { throw NativeIndexFailure.invalid("empty index coverage") }
        checked=true;return
      }
      guard let root=catalog.root,root.first==0,root.count==catalog.records,
        root.spanStart==0,root.spanEnd==catalog.indexBytes,catalog.payloadEnd>=payloadStart else { throw NativeIndexFailure.invalid("index root coverage") }
      var expected=payloadStart,seen:UInt64=0
      try walk(root) { record in
        guard record.offset==expected,expected<=self.catalog.payloadEnd,
          record.length<=self.catalog.payloadEnd-expected else { throw NativeIndexFailure.invalid("overlapping, missing or invalid payload range") }
        expected += record.length;seen += 1
      }
      guard expected==catalog.payloadEnd,seen==catalog.records else { throw NativeIndexFailure.invalid("unindexed payload bytes") }
      checked=true
    }
    func record(at ordinal:UInt64)throws->Record {
      try Task.checkCancellation()
      guard checked,ordinal<catalog.records,let root=catalog.root else { throw NativeIndexFailure.invalid("unvalidated or missing blob ordinal") }
      var reference=root
      while true {
        switch try node(reference) {
        case .leaf(let records): return records[Int(ordinal-reference.first)]
        case .branch(let children):
          var low=0,high=children.count
          while low<high {let middle=(low+high)/2;if children[middle].first<=ordinal {low=middle+1}else{high=middle}}
          guard low>0 else {throw NativeIndexFailure.invalid("missing child ordinal")}
          let child=children[low-1]
          guard ordinal-child.first<child.count else {throw NativeIndexFailure.invalid("child ordinal gap")}
          reference=child
        }
      }
    }
    private func walk(_ reference:Reference,_ visit:(Record)throws->Void)throws {
      try Task.checkCancellation()
      switch try node(reference) {
      case .leaf(let records):for record in records {try Task.checkCancellation();try visit(record)}
      case .branch(let children):for child in children {try walk(child,visit)}
      }
    }
    private func node(_ reference:Reference)throws->Node {
      try Task.checkCancellation()
      guard (0...maximumLevel).contains(reference.level),reference.length>=32,
        reference.length<=maximumNodeBytes,reference.digest.count==32,
        reference.offset<=catalog.indexBytes,UInt64(reference.length)<=catalog.indexBytes-reference.offset,
        reference.spanStart<=reference.offset,reference.spanEnd==reference.offset+UInt64(reference.length),
        reference.count>0,reference.first<=catalog.records,reference.count<=catalog.records-reference.first else {
        throw NativeIndexFailure.invalid("node reference bounds")
      }
      if let item=cache[reference.offset],item.0==reference{return item.1}
      let data=try read(reference.offset,reference.length);nodeReads+=1
      guard data.count==reference.length,Data(SHA256.hash(data:data))==reference.digest else {throw NativeIndexFailure.invalid("node integrity")}
      var c=Cursor(data)
      guard try c.bytes(8)==magic else {throw NativeIndexFailure.invalid("node magic")}
      let level=Int(try c.u32()),entries=Int(try c.u32()),first=try c.u64(),count=try c.u64()
      guard level==reference.level,first==reference.first,count==reference.count else {throw NativeIndexFailure.invalid("node header/reference mismatch")}
      let result:Node
      if level==0 {
        guard entries>0,entries<=leafCapacity,count==UInt64(entries),data.count==32+entries*48,
          reference.spanStart==reference.offset else {throw NativeIndexFailure.invalid("leaf shape")}
        var records:[Record]=[];records.reserveCapacity(entries)
        for _ in 0..<entries {records.append(Record(offset:try c.u64(),length:try c.u64(),digest:try c.bytes(32)))}
        result = .leaf(records)
      }else{
        guard entries>0,entries<=branchCapacity,data.count==32+entries*80 else {throw NativeIndexFailure.invalid("branch shape")}
        var children:[Reference]=[];children.reserveCapacity(entries)
        var next=first,end=reference.spanStart
        for _ in 0..<entries {
          let child=try decode(&c)
          guard child.level==level-1,child.first==next,child.count>0,child.count<=UInt64.max-next,
            child.spanStart==end,child.spanEnd>child.spanStart else {throw NativeIndexFailure.invalid("child coverage")}
          next += child.count;end=child.spanEnd;children.append(child)
        }
        guard next-first==count,end==reference.offset else {throw NativeIndexFailure.invalid("branch subtree coverage")}
        result = .branch(children)
      }
      guard c.at==data.count else {throw NativeIndexFailure.invalid("extra node bytes")}
      if cacheLimit>0 {
        if cache.count==cacheLimit {cache.removeValue(forKey:order.removeFirst())}
        cache[reference.offset]=(reference,result);order.append(reference.offset)
        maximumCachedNodes=max(maximumCachedNodes,cache.count)
      }
      return result
    }
  }

  private static func header(level:Int,entries:Int,first:UInt64,count:UInt64)->Data {
    var d=magic;put32(UInt32(level),into:&d);put32(UInt32(entries),into:&d);put(first,into:&d);put(count,into:&d);return d
  }
  private static func encode(_ ref:Reference,into d:inout Data) {
    put(ref.offset,into:&d);put32(UInt32(ref.length),into:&d);put32(UInt32(ref.level),into:&d)
    put(ref.first,into:&d);put(ref.count,into:&d);put(ref.spanStart,into:&d);put(ref.spanEnd,into:&d);d.append(ref.digest)
  }
  private static func decode(_ c:inout Cursor)throws->Reference {
    Reference(offset:try c.u64(),length:Int(try c.u32()),level:Int(try c.u32()),first:try c.u64(),count:try c.u64(),spanStart:try c.u64(),spanEnd:try c.u64(),digest:try c.bytes(32))
  }
  private static func put(_ n:UInt64,into d:inout Data) {var v=n.littleEndian;withUnsafeBytes(of:&v){d.append(contentsOf:$0)}}
  private static func put32(_ n:UInt32,into d:inout Data) {var v=n.littleEndian;withUnsafeBytes(of:&v){d.append(contentsOf:$0)}}
  private struct Cursor {
    let data:Data
    var at=0
    init(_ data:Data){self.data=data}
    mutating func bytes(_ n:Int)throws->Data {
      guard n>=0,at<=data.count,n<=data.count-at else {throw NativeIndexFailure.invalid("truncated node")}
      let start=data.startIndex+at;at+=n;return data.subdata(in:start..<start+n)
    }
    mutating func u32()throws->UInt32 {try bytes(4).withUnsafeBytes{UInt32(littleEndian:$0.loadUnaligned(as:UInt32.self))}}
    mutating func u64()throws->UInt64 {try bytes(8).withUnsafeBytes{UInt64(littleEndian:$0.loadUnaligned(as:UInt64.self))}}
  }
}

/// Owned append-only temporary index stream. It is unlinked immediately and all
/// physical I/O is bounded to64KiB; no array grows with the number of records.
final class NativeIndexScratch {
  private let fd:Int32
  private let maximumBytes:Int
  private(set) var count=0
  private(set) var maximumPhysicalIO=0
  init(maximumBytes:Int=4_398_046_511_104,directory:URL?=nil)throws {
    let parent=directory ?? FileManager.default.temporaryDirectory
    guard parent.isFileURL,maximumBytes>=0,maximumBytes<=4_398_046_511_104 else {throw NativeIndexFailure.invalid("scratch capacity/directory")}
    let url=parent.appendingPathComponent("photato-index-\(UUID().uuidString).tmp")
    let descriptor=url.withUnsafeFileSystemRepresentation{$0.map{open($0,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,S_IRUSR|S_IWUSR)} ?? -1}
    guard descriptor>=0 else {throw NativeIndexFailure.io("creation",errno)}
    let removed=url.withUnsafeFileSystemRepresentation{$0.map{unlink($0)} ?? -1}
    guard removed==0 else {let error=errno;close(descriptor);throw NativeIndexFailure.io("unlink",error)}
    fd=descriptor;self.maximumBytes=maximumBytes
  }
  deinit{close(fd)}
  func append(_ bytes:Data)throws->UInt64 {
    try Task.checkCancellation()
    guard bytes.count<=maximumBytes-count else {throw NativeIndexFailure.capacity(required:count+bytes.count,limit:maximumBytes)}
    let start=count
    try bytes.withUnsafeBytes { p in
      var done=0
      while done<p.count {
        try Task.checkCancellation();let size=min(65536,p.count-done);maximumPhysicalIO=max(maximumPhysicalIO,size)
        let n=pwrite(fd,p.baseAddress!.advanced(by:done),size,off_t(start+done))
        if n<0 && errno==EINTR {continue}
        guard n>0 else {throw NativeIndexFailure.io("write",n==0 ? EIO:errno)}
        done += n
      }
    }
    count += bytes.count;return UInt64(start)
  }
  func read(_ offset:UInt64,_ length:Int)throws->Data {
    try Task.checkCancellation()
    guard offset<=UInt64(count),length>=0,UInt64(length)<=UInt64(count)-offset else {throw NativeIndexFailure.invalid("scratch read range")}
    var data=Data(count:length)
    try data.withUnsafeMutableBytes { p in
      var done=0
      while done<p.count {
        try Task.checkCancellation();let size=min(65536,p.count-done);maximumPhysicalIO=max(maximumPhysicalIO,size)
        let n=pread(fd,p.baseAddress!.advanced(by:done),size,off_t(offset+UInt64(done)))
        if n<0 && errno==EINTR {continue}
        guard n>0 else {throw NativeIndexFailure.io("read",n==0 ? EIO:errno)}
        done += n
      }
    }
    return data
  }
}
