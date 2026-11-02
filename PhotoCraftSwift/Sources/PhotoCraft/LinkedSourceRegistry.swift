import AppKit
import CryptoKit
import Darwin
import Foundation
import PhotoCraftCore

struct LinkedArtworkGrant:Sendable {
  let id:UUID
  let generation:UUID
  let reference:String
  let url:URL
  let scopeURL:URL
  var sourceReference:String? = nil
}
@MainActor final class LinkedSourceRegistry {
  static let shared=LinkedSourceRegistry()
  struct PackageBinding:Codable,Equatable {let documentID:UUID;let reference:String;var documentName:String? = nil}
  struct Record:Codable {
    let id:UUID
    var generation:UUID
    let reference:String
    var bookmark:Data
    var securityScoped:Bool
    var packageBindings:[PackageBinding]? = nil
  }
  private var records:[UUID:Record]=[:]
  let storageURL:URL?
  init(storageURL:URL?=nil,persistent:Bool=true) {
    self.storageURL=persistent ? storageURL ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Photato/LinkedArtwork/authorizations.json"):nil
    if let path=self.storageURL,let size=try? path.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=16*1024*1024,
      let data=try? Data(contentsOf:path),let values=try? JSONDecoder().decode([Record].self,from:data),values.count<=512 {
      for value in values where value.bookmark.count<=1024*1024 && value.reference.utf8.count<=16384 {records[value.id]=value}
    }
  }
  private func save()throws {
    guard let storageURL else{return}
    try FileManager.default.createDirectory(at:storageURL.deletingLastPathComponent(),withIntermediateDirectories:true)
    let data=try JSONEncoder().encode(records.values.sorted{$0.id.uuidString<$1.id.uuidString})
    try data.write(to:storageURL,options:.atomic)
  }
  /// Called only after native file selection, or inside an already approved save directory.
  func authorize(_ selected:URL)throws->LinkedArtworkGrant {
    guard selected.isFileURL else{throw CraftError.invalid("Choose a local artwork file.")}
    let access=selected.startAccessingSecurityScopedResource();defer{if access{selected.stopAccessingSecurityScopedResource()}}
    let url=try Self.physicalURL(selected)
    let reference=url.absoluteString
    var scoped=true
    let bookmark:Data
    do{bookmark=try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil)}
    catch{scoped=false;bookmark=try url.bookmarkData(options:.minimalBookmark,includingResourceValuesForKeys:nil,relativeTo:nil)}
    guard bookmark.count<=1024*1024 else{throw CraftError.invalid("The source authorization is too large.")}
    let existing=records.values.first{$0.reference==reference}
    guard existing != nil || records.count<512 else{throw CraftError.invalid("Remove an unused artwork authorization before adding another.")}
    let id=existing?.id ?? UUID(),record=Record(id:id,generation:UUID(),reference:reference,bookmark:bookmark,securityScoped:scoped)
    var updated=record;updated.packageBindings=existing?.packageBindings
    let previous=records[id];records[id]=updated
    do{try save()}catch{records[id]=previous;throw error}
    return try resolve(id,reference:reference)
  }
  static func isPackageReference(_ text:String)->Bool {
    let parts=text.split(separator:"/",omittingEmptySubsequences:false)
    guard parts.count==2,parts[0]=="Links",!parts[1].isEmpty,!parts[1].hasPrefix("."),parts[1].utf8.count<=200 else{return false}
    return !parts[1].contains(":") && !parts[1].contains("\\") && !parts[1].unicodeScalars.contains(where:CharacterSet.controlCharacters.contains)
  }
  func resolve(_ link:LinkedSmartObjectSource,documentID:UUID?=nil,documentURL:URL?=nil)throws->LinkedArtworkGrant {
    guard link.kind == .file else{throw CraftError.invalid("Locate and authorize this linked artwork file.")}
    if let id=link.authorizationID{return try resolve(id,reference:link.reference)}
    if Self.isPackageReference(link.reference),let documentID,let documentURL {
      let parent=try Self.physicalURL(documentURL.deletingLastPathComponent())
      let expected=parent.appendingPathComponent(link.reference).path
      for record in records.values where record.packageBindings?.contains(where:{$0.reference==link.reference && ($0.documentID==documentID || $0.documentName==documentURL.lastPathComponent)})==true {
        if var grant=try? resolve(record.id),LinkedArtworkRead.sameFile(grant,at:URL(fileURLWithPath:expected)) {grant.sourceReference=link.reference;return grant}
      }
    }
    throw CraftError.invalid("Locate and authorize this linked artwork file or its package folder.")
  }
  /// The native folder picker grants this exact package, never a document-supplied path.
  func authorizePackage(_ folder:URL,document:CraftDocument,documentURL:URL)throws {
    let access=folder.startAccessingSecurityScopedResource();defer{if access{folder.stopAccessingSecurityScopedResource()}}
    let root=try Self.physicalURL(folder),expectedRoot=try Self.physicalURL(documentURL.deletingLastPathComponent())
    guard root.path==expectedRoot.path else{throw CraftError.invalid("Choose the folder containing this packaged document.")}
    let references=Set(document.layers.compactMap{$0.smartObject?.linkedSource}.filter{$0.kind == .file && Self.isPackageReference($0.reference)}.map(\.reference))
    guard !references.isEmpty else{throw CraftError.invalid("This document has no relative package links.")}
    let previous=records
    do {
      for reference in references.sorted() {
        let selected=root.appendingPathComponent(reference),physical=try Self.physicalURL(selected)
        guard physical.path==selected.path else{throw CraftError.invalid("Package sources cannot be symbolic links. Relink the source explicitly.")}
        let grant=try authorize(physical),binding=PackageBinding(documentID:document.id,reference:reference,documentName:documentURL.lastPathComponent)
        if var record=records[grant.id],record.packageBindings?.contains(binding) != true {record.packageBindings=(record.packageBindings ?? [])+[binding];records[grant.id]=record}
      }
      try save()
    }catch{records=previous;try? save();throw error}
  }
  func resolve(_ id:UUID,reference:String?=nil)throws->LinkedArtworkGrant {
    guard let record=records[id],reference==nil || record.reference==reference else{throw CraftError.invalid("The linked artwork is not authorized on this Mac.")}
    var stale=false
    var options:URL.BookmarkResolutionOptions=[.withoutUI,.withoutMounting]
    if record.securityScoped{options.insert(.withSecurityScope)}
    let scope=try URL(resolvingBookmarkData:record.bookmark,options:options,relativeTo:nil,bookmarkDataIsStale:&stale)
    guard scope.isFileURL,let original=URL(string:record.reference),original.isFileURL else{throw CraftError.invalid("Invalid local artwork authorization.")}
    // Prefer the approved pathname for atomic saves; bookmark identity follows moves.
    let current=FileManager.default.fileExists(atPath:original.path) ? original:scope
    let canonical=try Self.physicalURL(current)
    guard canonical.path==current.path else{throw CraftError.invalid("The artwork location became a symbolic link. Relink it explicitly.")}
    return .init(id:id,generation:record.generation,reference:record.reference,url:canonical,scopeURL:scope)
  }
  /// Foundation standardization can turn /private/var back into the /var symlink.
  /// Authorize a physical pathname once, then require that pathname to stay physical.
  private static func physicalURL(_ url:URL)throws->URL {
    let resolved=url.withUnsafeFileSystemRepresentation {pointer -> UnsafeMutablePointer<CChar>? in
      guard let pointer else{return nil};return Darwin.realpath(pointer,nil)
    }
    guard let resolved else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
    defer{Darwin.free(resolved)}
    return URL(fileURLWithFileSystemRepresentation:resolved,isDirectory:false,relativeTo:nil)
  }
  func stillAuthorizes(_ grant:LinkedArtworkGrant)->Bool {
    guard let value=records[grant.id] else{return false};return value.generation==grant.generation && value.reference==grant.reference
  }
  func revoke(_ id:UUID)throws {let previous=records.removeValue(forKey:id);do{try save()}catch{records[id]=previous;throw error}}
}

struct LinkedArtworkRead:Sendable {
  let data:Data
  let fingerprint:String
  let signature:String
  let modified:Date
  let fileName:String
  let grant:LinkedArtworkGrant
  var reference:LinkedSmartObjectSource {get throws{try .init(reference:grant.sourceReference ?? grant.reference,authorizationID:grant.sourceReference==nil ? grant.id:nil,contentHash:fingerprint,byteLength:UInt64(data.count),modificationDate:modified)}}
  private static func error()->NSError {NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
  private static func openApproved(_ url:URL)throws->Int32 {
    guard url.isFileURL,url.path.hasPrefix("/")else{throw CraftError.invalid("Choose a local artwork file.")}
    var parent=Darwin.open("/",O_SEARCH|O_CLOEXEC);guard parent>=0 else{throw error()}
    defer{Darwin.close(parent)}
    let pieces=url.pathComponents.filter{$0 != "/"}
    guard let file=pieces.last,!pieces.contains("..")else{throw CraftError.invalid("Invalid artwork path.")}
    for component in pieces.dropLast() {
      let next=component.withCString{openat(parent,$0,O_SEARCH|O_NOFOLLOW|O_CLOEXEC)}
      guard next>=0 else{throw error()};Darwin.close(parent);parent=next
    }
    let fd=file.withCString{openat(parent,$0,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)}
    guard fd>=0 else{throw error()};return fd
  }
  private static func signature(_ s:stat)->String {"\(s.st_dev):\(s.st_ino):\(s.st_size):\(s.st_mtimespec.tv_sec):\(s.st_mtimespec.tv_nsec):\(s.st_ctimespec.tv_sec):\(s.st_ctimespec.tv_nsec)"}
  private static func info(_ fd:Int32)throws->stat {
    var value=stat();guard fstat(fd,&value)==0 else{throw error()}
    guard value.st_mode&S_IFMT==S_IFREG,value.st_size>0,value.st_size<=SmartObject.maximumSourceBytes else{throw CraftError.invalid("Linked artwork must be a regular file between1 byte and64MiB.")};return value
  }
  static func sameFile(_ grant:LinkedArtworkGrant,at expected:URL)->Bool {
    let access=grant.scopeURL.startAccessingSecurityScopedResource();defer{if access{grant.scopeURL.stopAccessingSecurityScopedResource()}}
    do {
      let approved=try openApproved(grant.url);defer{Darwin.close(approved)}
      let candidate=try openApproved(expected);defer{Darwin.close(candidate)}
      let a=try info(approved),b=try info(candidate);return a.st_dev==b.st_dev && a.st_ino==b.st_ino
    }catch{return false}
  }
  static func signature(_ grant:LinkedArtworkGrant)throws->String {
    let access=grant.scopeURL.startAccessingSecurityScopedResource();defer{if access{grant.scopeURL.stopAccessingSecurityScopedResource()}}
    let fd=try openApproved(grant.url);defer{Darwin.close(fd)};return signature(try info(fd))
  }
  static func read(_ grant:LinkedArtworkGrant)throws->Self {
    let access=grant.scopeURL.startAccessingSecurityScopedResource();defer{if access{grant.scopeURL.stopAccessingSecurityScopedResource()}}
    let fd=try openApproved(grant.url);defer{Darwin.close(fd)};let before=try info(fd)
    var data=Data(),buffer=[UInt8](repeating:0,count:65536),hash=SHA256()
    while data.count<Int(before.st_size) {
      try Task.checkCancellation();let amount=buffer.withUnsafeMutableBytes{pread(fd,$0.baseAddress,min($0.count,Int(before.st_size)-data.count),off_t(data.count))}
      if amount<0 {if errno==EINTR{continue};throw error()};guard amount>0 else{throw DocumentPersistenceConflict.changed}
      let part=Data(buffer.prefix(amount));data.append(part);hash.update(data:part)
    }
    let after=try info(fd),current=try openApproved(grant.url);defer{Darwin.close(current)}
    guard signature(before)==signature(after),signature(before)==signature(try info(current)) else{throw DocumentPersistenceConflict.changed}
    return .init(data:data,fingerprint:hash.finalize().map{String(format:"%02x",$0)}.joined(),signature:signature(before),modified:Date(timeIntervalSince1970:Double(before.st_mtimespec.tv_sec)+Double(before.st_mtimespec.tv_nsec)/1e9),fileName:grant.url.lastPathComponent,grant:grant)
  }
}
