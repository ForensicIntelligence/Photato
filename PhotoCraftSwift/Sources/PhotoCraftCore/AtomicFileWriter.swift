import Darwin
import Foundation

/// A single-owner, bounded file transaction. Only commit replaces the destination;
/// cancellation/errors discard the private sibling file. AppKit callers still use
/// NSDocument's coordination, attributes and version handling around this writer.
public final class AtomicFileWriter {
  public static let chunkBytes = 64 * 1024
  public private(set) var count = 0
  public private(set) var maximumWriteBytes = 0
  private let maximumBytes: Int
  private let destination: URL
  private let parent: URL
  private let destinationName: String
  private let temporaryName: String
  private let operations: Operations
  private var descriptor: Int32 = -1
  private var directoryDescriptor: Int32 = -1
  private var directoryIdentity: Identity?
  private var stagedIdentity: Identity?
  private var committed = false
  private var ownsTemporary = false
  private var failed = false
  private var original: Identity?
  private let requestedVisibility: Bool?
  private let followSymbolicLinks: Bool

  public enum Synchronization: String, Sendable { case full, file }
  public private(set) var synchronization: Synchronization?

  // Per-transaction syscall injection, never a process-wide override.
  struct Operations {
    var write: (Int32, UnsafeRawPointer?, Int, off_t) -> Int = {
      Darwin.pwrite($0, $1, $2, $3)
    }
    var synchronize: (Int32) -> Int32 = { Darwin.fsync($0) }
    var fullSynchronize: (Int32) -> Int32 = { Darwin.fcntl($0, F_FULLFSYNC) }
    var setFlags: (Int32, UInt32) -> Int32 = { Darwin.fchflags($0, $1) }
    var rename: (Int32, String, String) -> Int32 = { directory, from, to in
      from.withCString { source in
        to.withCString { destination in Darwin.renameat(directory, source, directory, destination) }
      }
    }
  }

  private struct Identity: Equatable {
    var device: dev_t
    var inode: ino_t
    var size: off_t
    var mode: mode_t
    var flags: UInt32
    var modified: timespec
    var changed: timespec
    static func == (a: Self, b: Self) -> Bool {
      a.device == b.device && a.inode == b.inode && a.size == b.size && a.mode == b.mode
        && a.flags == b.flags
        && a.modified.tv_sec == b.modified.tv_sec && a.modified.tv_nsec == b.modified.tv_nsec
        && a.changed.tv_sec == b.changed.tv_sec && a.changed.tv_nsec == b.changed.tv_nsec
    }
  }

  /// A coordinating outer save may provide its final destination's visibility
  /// when this transaction writes to an intermediate URL owned by that save.
  public convenience init(to url: URL, maximumBytes: Int = 512 * 1024 * 1024,
    destinationHidden: Bool? = nil, followSymbolicLinks: Bool = true) throws {
    try self.init(to: url, maximumBytes: maximumBytes,
      destinationHidden: destinationHidden, followSymbolicLinks: followSymbolicLinks, operations: Operations())
  }

  init(to url: URL, maximumBytes: Int = 512 * 1024 * 1024,
    destinationHidden: Bool? = nil, followSymbolicLinks: Bool = true, operations: Operations) throws {
    try Task.checkCancellation()
    guard url.isFileURL, maximumBytes >= 0 else {
      throw CraftError.invalid("Choose a local file and a valid output limit.")
    }
    self.followSymbolicLinks = followSymbolicLinks
    destination = followSymbolicLinks ? url.standardizedFileURL.resolvingSymlinksInPath() : url
    parent = destination.deletingLastPathComponent()
    destinationName = destination.lastPathComponent
    temporaryName = ".photato-save-" + UUID().uuidString
    self.operations = operations
    requestedVisibility = destinationHidden
    self.maximumBytes = maximumBytes
    if followSymbolicLinks {
      directoryDescriptor = parent.withUnsafeFileSystemRepresentation { path in
        path.map { Darwin.open($0, O_SEARCH | O_NOFOLLOW | O_CLOEXEC) } ?? -1
      }
    }else{directoryDescriptor = try Self.openPhysicalDirectory(parent)}
    guard directoryDescriptor >= 0 else { throw Self.posixError() }
    do {
      directoryIdentity = try Self.identity(descriptor: directoryDescriptor)
      try validateParent()
      original = try Self.identity(directory: directoryDescriptor, name: destinationName)
      descriptor = temporaryName.withCString {
        Darwin.openat(directoryDescriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
      }
      guard descriptor >= 0 else { throw Self.posixError() }
      ownsTemporary = true
      stagedIdentity = try Self.identity(descriptor: descriptor)
    } catch {
      discard()
      closeDirectory()
      throw error
    }
  }

  deinit {
    discard()
    closeDirectory()
  }

  /// End an unsuccessful transaction promptly even when an encoder temporarily
  /// retains the sink. Never removes a committed destination.
  public func discard() {
    failed = true
    if descriptor >= 0 {
      Darwin.close(descriptor)
      descriptor = -1
    }
    if ownsTemporary && !committed {
      var value = stat()
      let found = temporaryName.withCString {
        fstatat(directoryDescriptor, $0, &value, AT_SYMLINK_NOFOLLOW)
      }
      if found == 0, let stagedIdentity {
        if Self.sameFile(stagedIdentity, Self.identity(value)) {
          let removed = temporaryName.withCString { Darwin.unlinkat(directoryDescriptor, $0, 0) }
          if removed == 0 || errno == ENOENT { ownsTemporary = false }
        } else {
          // The private name has been replaced. It no longer belongs to us.
          ownsTemporary = false
        }
      } else if found != 0 && errno == ENOENT {
        ownsTemporary = false
      }
    }
    if !ownsTemporary { closeDirectory() }
  }

  public func append(_ data: Data) throws {
    guard data.count <= maximumBytes - count else {
      failed = true
      throw CraftError.invalid("Document export exceeds the file size budget.")
    }
    try write(data, at: count)
    count += data.count
  }

  /// Backpatch existing bytes only. No sparse extension or unchecked integer casts.
  public func patch(_ data: Data, at offset: Int) throws {
    guard offset >= 0, offset <= count, data.count <= count - offset else {
      throw CraftError.invalid("Invalid output patch range.")
    }
    try write(data, at: offset)
  }

  private func write(_ data: Data, at offset: Int) throws {
    try Task.checkCancellation()
    guard descriptor >= 0, !committed, !failed else {
      throw CraftError.invalid("The file transaction is already closed.")
    }
    do {
      try data.withUnsafeBytes { bytes in
        var written = 0
        while written < bytes.count {
          try Task.checkCancellation()
          let requested = min(Self.chunkBytes, bytes.count - written)
          let amount = operations.write(
            descriptor, bytes.baseAddress!.advanced(by: written), requested, off_t(offset + written)
          )
          maximumWriteBytes = max(maximumWriteBytes, requested)
          if amount < 0 {
            if errno == EINTR { continue }
            throw Self.posixError()
          }
          guard amount > 0 else { throw CraftError.invalid("The file write made no progress.") }
          written += amount
        }
      }
    } catch {
      failed = true
      throw error
    }
  }

  public func commit() throws {
    try Task.checkCancellation()
    guard descriptor >= 0, !committed, !failed else {
      throw CraftError.invalid("The file transaction is already closed.")
    }
    do {
      if let original {
        guard fchmod(descriptor, original.mode & 0o777) == 0 else { throw Self.posixError() }
      }
      try prepareVisibility()
      while operations.synchronize(descriptor) != 0 {
        if errno != EINTR { throw Self.posixError() }
        try Task.checkCancellation()
      }
      while true {
        try Task.checkCancellation()
        if operations.fullSynchronize(descriptor) == 0 {
          synchronization = .full
          break
        }
        let code = errno
        if code == EINTR { continue }
        if [EINVAL, ENOTSUP, ENOSYS].contains(code) {
          // Some destinations do not implement F_FULLFSYNC. The preceding fsync
          // still succeeded. Do not disguise actual I/O/space errors as fallback.
          synchronization = .file
          break
        }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
      }
      try Task.checkCancellation()
      try validateParent()
      guard try Self.identity(directory: directoryDescriptor, name: destinationName) == original
      else {
        throw CraftError.invalid("The destination changed while preparing the save. Save again.")
      }
      let opened = try Self.identity(descriptor: descriptor)
      let named = try Self.identity(directory: directoryDescriptor, name: temporaryName)
      guard let named, Self.sameFile(opened, named), opened.size == count,
        opened.flags & UInt32(UF_HIDDEN) == destinationVisibility
      else {
        throw CraftError.invalid("The staged file changed while preparing the save. Save again.")
      }
      // Relative publication stays in the opened directory even if its path moves
      // after validation. NSDocument still owns higher-level file coordination.
      guard operations.rename(directoryDescriptor, temporaryName, destinationName) == 0 else {
        throw Self.posixError()
      }
      committed = true
      ownsTemporary = false
      Darwin.close(descriptor)
      descriptor = -1
      closeDirectory()
    } catch {
      failed = true
      throw error
    }
  }

  private var destinationVisibility: UInt32 {
    if let requestedVisibility { return requestedVisibility ? UInt32(UF_HIDDEN) : 0 }
    return (original?.flags ?? 0) & UInt32(UF_HIDDEN)
  }

  private func prepareVisibility() throws {
    // File Provider can mark the dot-prefixed private sibling UF_HIDDEN. That
    // staging attribute must not leak into a new visible document. Preserve an
    // existing destination's intentional visibility and all other staging flags.
    while true {
      try Task.checkCancellation()
      let current = try Self.identity(descriptor: descriptor).flags
      let desired = (current & ~UInt32(UF_HIDDEN)) | destinationVisibility
      if current == desired { return }
      if operations.setFlags(descriptor, desired) == 0 { return }
      if errno != EINTR { throw Self.posixError() }
    }
  }

  private func closeDirectory() {
    if directoryDescriptor >= 0 {
      Darwin.close(directoryDescriptor)
      directoryDescriptor = -1
    }
  }

  /// A previously authorized physical path must not gain a symlink at any component.
  private static func openPhysicalDirectory(_ url:URL)throws->Int32 {
    guard url.isFileURL,url.path.hasPrefix("/"),!url.pathComponents.contains("..") else{throw CraftError.invalid("Choose an absolute physical destination.")}
    var fd=Darwin.open("/",O_SEARCH|O_DIRECTORY|O_CLOEXEC)
    guard fd>=0 else{throw posixError()}
    do {
      for part in url.pathComponents where part != "/" {
        let next=part.withCString{Darwin.openat(fd,$0,O_SEARCH|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)}
        guard next>=0 else{throw posixError()};Darwin.close(fd);fd=next
      }
      return fd
    }catch{Darwin.close(fd);throw error}
  }

  private func validateParent() throws {
    if !followSymbolicLinks {
      let fd=try Self.openPhysicalDirectory(parent);defer{Darwin.close(fd)}
      guard let directoryIdentity,Self.sameFile(directoryIdentity,try Self.identity(descriptor:fd))else{throw CraftError.invalid("The destination folder changed while preparing the save.")}
      return
    }
    var value = stat()
    let result = parent.withUnsafeFileSystemRepresentation { path in
      path.map { fstatat(AT_FDCWD, $0, &value, AT_SYMLINK_NOFOLLOW) } ?? -1
    }
    guard result == 0, value.st_mode & S_IFMT == S_IFDIR,
      let directoryIdentity, Self.sameFile(directoryIdentity, Self.identity(value))
    else { throw CraftError.invalid("The destination folder changed while preparing the save.") }
  }

  private static func sameFile(_ a: Identity, _ b: Identity) -> Bool {
    a.device == b.device && a.inode == b.inode
  }

  private static func identity(descriptor: Int32) throws -> Identity {
    var value = stat()
    guard fstat(descriptor, &value) == 0 else { throw posixError() }
    return identity(value)
  }

  private static func identity(directory: Int32, name: String) throws -> Identity? {
    var value = stat()
    let result = name.withCString { fstatat(directory, $0, &value, AT_SYMLINK_NOFOLLOW) }
    if result != 0 {
      if errno == ENOENT { return nil }
      throw posixError()
    }
    guard value.st_mode & S_IFMT == S_IFREG else {
      throw CraftError.invalid("The save destination must be a regular file.")
    }
    return identity(value)
  }

  private static func identity(_ value: stat) -> Identity {
    Identity(
      device: value.st_dev, inode: value.st_ino, size: value.st_size, mode: value.st_mode,
      flags: value.st_flags,
      modified: value.st_mtimespec, changed: value.st_ctimespec)
  }

  private static func posixError() -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
  }
}
