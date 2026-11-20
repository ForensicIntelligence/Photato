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
  var sourceLink: LinkedSmartObjectSource? = nil

  func updatedLink(fingerprint: String, byteLength: UInt64, modified: Date?) throws -> LinkedSmartObjectSource {
    try LinkedSmartObjectSource(reference: sourceLink?.reference ?? reference,
      authorizationID: sourceLink == nil ? id : sourceLink?.authorizationID,
      contentHash: fingerprint, byteLength: byteLength, modificationDate: modified,
      relativePath: sourceLink?.relativePath)
  }
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
    try register(selected, persist: true)
  }
  private func register(_ selected: URL, persist: Bool, expectedPath: String? = nil) throws -> LinkedArtworkGrant {
    guard selected.isFileURL else{throw CraftError.invalid("Choose a local artwork file.")}
    let access=selected.startAccessingSecurityScopedResource();defer{if access{selected.stopAccessingSecurityScopedResource()}}
    let url=try Self.physicalURL(selected)
    if let expectedPath, url.path != expectedPath { throw DocumentPersistenceConflict.changed }
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
    do {
      let grant = try resolve(id, reference: reference)
      if persist { try save() }
      return grant
    } catch {
      records[id] = previous
      throw error
    }
  }

  private nonisolated static func localSubpath(_ path: String) -> String? {
    guard LinkedSmartObjectSource.isRelativePath(path) else { return nil }
    let parts = path.replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/", omittingEmptySubsequences: false).filter { $0 != "." }
    guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && $0.utf8.count <= 255 })
    else { return nil }
    return parts.joined(separator: "/")
  }

  private nonisolated static func localCandidates(_ link: LinkedSmartObjectSource) -> (relative: String?, sibling: String?) {
    guard link.kind == .file else { return (nil, nil) }
    let relative = localSubpath(link.relativePath ?? link.reference)
    let source = link.relativePath ?? link.reference
    let basename = URL(string: source).flatMap { $0.isFileURL ? $0.lastPathComponent : nil }
      ?? source.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)
    let sibling = basename.flatMap(localSubpath)
    return (relative, sibling == relative ? nil : sibling)
  }

  nonisolated static func hasFolderCandidates(_ link: LinkedSmartObjectSource) -> Bool {
    let paths = localCandidates(link)
    return paths.relative != nil || (link.authorizationID == nil && paths.sibling != nil)
  }

  private func packageGrant(_ path: String?, documentID: UUID?, documentURL: URL?) -> LinkedArtworkGrant? {
    guard let path, let documentID, let documentURL else { return nil }
    let matches = records.values.filter { record in
      record.packageBindings?.contains(where: {
        $0.reference == path && ($0.documentID == documentID || $0.documentName == documentURL.lastPathComponent)
      }) == true
    }
    guard !matches.isEmpty, let parent = try? Self.physicalURL(documentURL.deletingLastPathComponent())
    else { return nil }
    let expected = parent.appendingPathComponent(path)
    for record in matches {
      if let grant = try? resolve(record.id), LinkedArtworkRead.sameFile(grant, at: expected) { return grant }
    }
    return nil
  }
  func resolve(_ link:LinkedSmartObjectSource,documentID:UUID?=nil,documentURL:URL?=nil)throws->LinkedArtworkGrant {
    guard link.kind == .file else{throw CraftError.invalid("Locate and authorize this linked artwork file.")}
    let paths = Self.localCandidates(link)
    if var grant = packageGrant(paths.relative, documentID: documentID, documentURL: documentURL) {
      grant.sourceLink = link
      return grant
    }
    if let id = link.authorizationID, var grant = try? resolve(id, reference: link.reference) {
      grant.sourceLink = link
      return grant
    }
    if var grant = packageGrant(paths.sibling, documentID: documentID, documentURL: documentURL) {
      grant.sourceLink = link
      return grant
    }
    throw CraftError.invalid("Locate and authorize this linked artwork file or its package folder.")
  }
  /// The native folder picker grants this exact package, never a document-supplied path.
  func authorizePackage(_ folder:URL,document:CraftDocument,documentURL:URL)throws {
    let access=folder.startAccessingSecurityScopedResource();defer{if access{folder.stopAccessingSecurityScopedResource()}}
    let root=try Self.physicalURL(folder),expectedRoot=try Self.physicalURL(documentURL.deletingLastPathComponent())
    guard root.path==expectedRoot.path else{throw CraftError.invalid("Choose the folder containing this packaged document.")}
    let references = Set(document.layers.compactMap { $0.smartObject?.linkedSource }
      .filter(Self.hasFolderCandidates).flatMap { link in
        let paths = Self.localCandidates(link)
        return [paths.relative, paths.sibling].compactMap { $0 }
      })
    let previous=records
    do {
      var found = false
      for reference in references.sorted() {
        let selected = root.appendingPathComponent(reference)
        guard let physical = try? Self.physicalURL(selected), physical.path == selected.path,
          (try? physical.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
        let grant = try register(physical, persist: false, expectedPath: selected.path)
        let binding = PackageBinding(documentID: document.id, reference: reference, documentName: documentURL.lastPathComponent)
        found = true
        if var record=records[grant.id],record.packageBindings?.contains(binding) != true {record.packageBindings=(record.packageBindings ?? [])+[binding];records[grant.id]=record}
      }
      guard found else { throw CraftError.invalid("No linked artwork was found in the document’s folder. Use Relink to File for the missing source.") }
      try save()
    }catch{records=previous;throw error}
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
  let original: EmbeddedSourceBytes
  var data: Data { original.data }
  let fingerprint:String
  let signature:String
  let modified:Date
  let fileName:String
  let grant:LinkedArtworkGrant
  var reference: LinkedSmartObjectSource {
    get throws { try grant.updatedLink(fingerprint: fingerprint, byteLength: UInt64(data.count), modified: modified) }
  }
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
    guard value.st_mode & S_IFMT == S_IFREG, value.st_size > 0,
      value.st_size <= SmartObject.maximumFileBackedSourceBytes else {
      throw CraftError.invalid("Linked artwork must be a regular file between 1 byte and 2 GiB.")
    }
    return value
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
    try read(grant, forTransfer: false)
  }
  static func readForTransfer(_ grant: LinkedArtworkGrant) throws -> Self {
    try read(grant, forTransfer: true)
  }
  private static func read(_ grant: LinkedArtworkGrant, forTransfer: Bool) throws -> Self {
    let access=grant.scopeURL.startAccessingSecurityScopedResource();defer{if access{grant.scopeURL.stopAccessingSecurityScopedResource()}}
    let fd=try openApproved(grant.url);defer{Darwin.close(fd)};let before=try info(fd)
    let size = Int(before.st_size)
    func bytes(at offset: Int, count: Int) throws -> Data {
      var bytes = Data(count: count)
      try bytes.withUnsafeMutableBytes { buffer in
        var done = 0
        while done < count {
          try Task.checkCancellation()
          let read = pread(fd, buffer.baseAddress!.advanced(by: done), count - done, off_t(offset + done))
          if read < 0, errno == EINTR { continue }
          if read < 0 { throw error() }
          guard read > 0 else { throw DocumentPersistenceConflict.changed }
          done += read
        }
      }
      return bytes
    }
    let requiresBacking = size > SmartObject.maximumSourceBytes
    if requiresBacking {
      if forTransfer { throw AutomationFailure(status: 413, message: "Linked original transfers are limited to 64 MiB.") }
      let header = try bytes(at: 0, count: min(size, 8))
      guard size <= SmartObject.maximumLocalEmbeddedBytes(forHeader: header) else {
        throw CraftError.invalid("Only layered Photoshop and Photato originals can exceed 64 MiB.")
      }
    }
    let original: EmbeddedSourceBytes
    let fingerprint: String
    if requiresBacking {
      let backing = try FileBackedSource.retain(byteCount: size, fingerprinting: true, read: bytes(at:count:))
      original = .file(backing)
      fingerprint = backing.fingerprint
    } else {
      var data = Data(capacity: size)
      var hash = SHA256()
      while data.count < size {
        let chunk = try bytes(at: data.count, count: min(65536, size - data.count))
        hash.update(data: chunk)
        data.append(chunk)
      }
      original = .memory(data)
      fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    let after=try info(fd),current=try openApproved(grant.url);defer{Darwin.close(current)}
    guard signature(before)==signature(after),signature(before)==signature(try info(current)) else{throw DocumentPersistenceConflict.changed}
    return .init(original:original,fingerprint:fingerprint,signature:signature(before),modified:Date(timeIntervalSince1970:Double(before.st_mtimespec.tv_sec)+Double(before.st_mtimespec.tv_nsec)/1e9),fileName:grant.url.lastPathComponent,grant:grant)
  }
}
