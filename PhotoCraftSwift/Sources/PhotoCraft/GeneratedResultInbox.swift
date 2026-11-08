import CryptoKit
import Darwin
import Foundation
import PhotoCraftAI
import PhotoCraftCore

/// Private durable originals. Atomic publication is independent of the source
/// document, so rejected placement and source closure cannot erase a result.
final class GeneratedResultInbox:@unchecked Sendable {
  static let archiveLimit=GenerationRecord.maximumOriginalBytes+64*1024
  static let shared:GeneratedResultInbox = {
    let isolated=ProcessInfo.processInfo.environment["PHOTATO_ISOLATED_UI_SESSION"]=="1" || CommandLine.arguments.contains{$0.hasPrefix("--snapshot")}
    let directory:URL?
    if isolated {
      let name=(Bundle.main.bundleIdentifier ?? "Photato").filter{$0.isLetter || $0.isNumber || $0=="." || $0=="-"}
      directory=FileManager.default.temporaryDirectory.appendingPathComponent("Photato-Isolated-GeneratedResults/"+name,isDirectory:true)
    }else{directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("Photato/Generated Results",isDirectory:true)}
    return GeneratedResultInbox(directory:directory)
  }()
  struct Entry:Identifiable,Sendable {
    let id:UUID,record:GenerationRecord?,storedBytes:Int,error:String?
    var date:Date {record?.acceptedAt ?? .distantPast}
  }
  struct FileIdentity:Equatable,Sendable {
    let device:Int32,inode:UInt64,size:Int64,modifiedSeconds:Int,modifiedNanoseconds:Int
  }
  func identity(_ id:UUID)throws->FileIdentity {
    let root=try root(create:false),url=root.appendingPathComponent(id.uuidString+".phtgen")
    var value=stat();guard lstat(url.path,&value)==0,(value.st_mode&S_IFMT)==S_IFREG else{throw CraftError.invalid("The saved result is no longer a regular file.")}
    return FileIdentity(device:value.st_dev,inode:value.st_ino,size:value.st_size,modifiedSeconds:value.st_mtimespec.tv_sec,modifiedNanoseconds:value.st_mtimespec.tv_nsec)
  }
  private struct Payload:Codable {let version:Int,record:GenerationRecord,original:Data}
  let directory:URL?
  let maximumBytes:Int,maximumEntries:Int
  private let lock=NSLock()
  private let write:@Sendable(URL,Data)throws->Void
  private let trash:@Sendable(URL)throws->Void
  init(directory:URL?,maximumBytes:Int=512*1024*1024,maximumEntries:Int=256,
    write:@escaping @Sendable(URL,Data)throws->Void = {url,bytes in
      let writer=try AtomicFileWriter(to:url,maximumBytes:GeneratedResultInbox.archiveLimit,followSymbolicLinks:false)
      defer{writer.discard()};try writer.append(bytes);try writer.commit()
    },trash:@escaping @Sendable(URL)throws->Void = {try FileManager.default.trashItem(at:$0,resultingItemURL:nil)}) {
    self.directory=directory;self.maximumBytes=maximumBytes;self.maximumEntries=maximumEntries;self.write=write;self.trash=trash
  }
  private func root(create:Bool)throws->URL {
    guard let directory,directory.isFileURL,maximumBytes>=0,maximumEntries>=0 else{throw CraftError.invalid("The generated-result inbox is unavailable.")}
    if create {try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])}
    if FileManager.default.fileExists(atPath:directory.path) {
      let value=try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
      guard value.isDirectory==true,value.isSymbolicLink != true else{throw CraftError.invalid("The generated-result inbox is not a private directory.")}
    }
    // Foundation can preserve the /var alias even after resolvingSymlinksInPath.
    // The strict writer needs the actual POSIX path after rejecting a symbolic root.
    if FileManager.default.fileExists(atPath:directory.path) {
      guard let physical=directory.withUnsafeFileSystemRepresentation({path in path.flatMap{Darwin.realpath($0,nil)}})else{throw CraftError.invalid("The generated-result inbox could not be resolved.")}
      defer{free(physical)}
      return URL(fileURLWithPath:String(cString:physical),isDirectory:true)
    }
    return directory
  }
  private func items(in root:URL)throws->[(UUID,URL,Int)] {
    guard FileManager.default.fileExists(atPath:root.path)else{return []}
    return try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.fileSizeKey],options:[.skipsHiddenFiles]).compactMap{url in
      guard url.pathExtension=="phtgen",let id=UUID(uuidString:url.deletingPathExtension().lastPathComponent)else{return nil}
      return(id,url,max(0,try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0))
    }
  }
  private func capacity(_ items:[(UUID,URL,Int)],adding bytes:Int)throws {
    var used=0
    for row in items {guard row.2<=maximumBytes-used else{throw CraftError.invalid("The generated-result inbox has reached its storage limit. Move saved results to Trash before generating again.")};used+=row.2}
    guard items.count<maximumEntries,bytes>=0,bytes<=maximumBytes-used else{throw CraftError.invalid("The generated-result inbox has reached its storage limit. Move saved results to Trash before generating again.")}
  }
  func preflight()throws {
    lock.lock();defer{lock.unlock()}
    let root=try root(create:true);try capacity(items(in:root),adding:Self.archiveLimit)
  }
  private func read(_ id:UUID,at url:URL)throws->Payload {
    let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
    guard values.isRegularFile==true,values.isSymbolicLink != true,let count=values.fileSize,count>0,count<=Self.archiveLimit else{throw CraftError.invalid("The saved generated result has an invalid size or file type.")}
    let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
    var data=Data()
    while let chunk=try file.read(upToCount:min(1024*1024,Self.archiveLimit-data.count+1)),!chunk.isEmpty {
      guard chunk.count<=Self.archiveLimit-data.count else{throw CraftError.invalid("The saved generated result exceeds its storage limit.")};data.append(chunk)
    }
    guard data.count==count else{throw CraftError.invalid("The saved generated result changed while reading.")}
    let payload=try PropertyListDecoder().decode(Payload.self,from:data);_ = try payload.record.encoded()
    guard payload.version==1,payload.record.requestID==id,payload.original.count==payload.record.originalByteCount,
      payload.original.count<=GenerationRecord.maximumOriginalBytes,
      SHA256.hash(data:payload.original).map({String(format:"%02x",$0)}).joined()==payload.record.originalSHA256 else{throw CraftError.invalid("The saved generated result does not match its record.")}
    return payload
  }
  @discardableResult func persist(_ record:GenerationRecord,original:Data)throws->UUID {
    lock.lock();defer{lock.unlock()};_ = try record.encoded()
    guard original.count==record.originalByteCount,SHA256.hash(data:original).map({String(format:"%02x",$0)}).joined()==record.originalSHA256 else{throw CraftError.invalid("The generated original does not match its record.")}
    let root=try root(create:true),file=root.appendingPathComponent(record.requestID.uuidString+".phtgen")
    if FileManager.default.fileExists(atPath:file.path) {
      let existing=try read(record.requestID,at:file)
      guard existing.record==record,existing.original==original else{throw CraftError.invalid("A different result already uses this request identifier.")};return record.requestID
    }
    let encoder=PropertyListEncoder();encoder.outputFormat = .binary
    let bytes=try encoder.encode(Payload(version:1,record:record,original:original))
    guard bytes.count<=Self.archiveLimit else{throw CraftError.invalid("The generated-result archive exceeds its byte limit.")}
    try capacity(items(in:root),adding:bytes.count)
    try write(file,bytes)
    return record.requestID
  }
  func load(_ id:UUID)throws->(GenerationRecord,Data) {
    lock.lock();defer{lock.unlock()};let root=try root(create:false),value=try read(id,at:root.appendingPathComponent(id.uuidString+".phtgen"));return(value.record,value.original)
  }
  func list()throws->[Entry] {
    lock.lock()
    let rows:[(UUID,URL,Int)]
    do {rows=try items(in:root(create:false));lock.unlock()}catch{lock.unlock();throw error}
    return try rows.map{id,url,count in
      try Task.checkCancellation()
      return autoreleasepool {
        do {let value=try read(id,at:url);return Entry(id:id,record:value.record,storedBytes:count,error:nil)}
        catch{return Entry(id:id,record:nil,storedBytes:count,error:error.localizedDescription)}
      }
    }.sorted{a,b in a.date==b.date ? a.id.uuidString<b.id.uuidString:a.date>b.date}
  }
  func moveToTrash(_ id:UUID)throws {
    lock.lock();defer{lock.unlock()};let root=try root(create:false),url=root.appendingPathComponent(id.uuidString+".phtgen")
    guard FileManager.default.fileExists(atPath:url.path)else{throw CraftError.invalid("That saved result is no longer available.")}
    try trash(url)
  }
}
