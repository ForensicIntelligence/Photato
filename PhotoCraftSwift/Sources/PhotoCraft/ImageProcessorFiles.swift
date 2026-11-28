import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Stage complete outputs, then publish without replacing files or following
/// symlinked format folders. Any failed commit rolls back its own new files.
struct PreparedImageProcessorFiles: Sendable {
  let staging: URL
  private let names: [String]

  static func prepare(_ output: ImageProcessor.Output, parent: URL) throws -> Self {
    let files = output.files.filter { $0.name != "image-processor.json" }
    return try stage(parent: parent, names: files.map(\.name)) { index, url in
      let writer = try AtomicFileWriter(to: url, maximumBytes: ImageProcessor.maximumBytes)
      try writer.append(files[index].data)
      try writer.commit()
    }
  }

  static func stage(parent: URL, names: [String], write: (Int, URL) throws -> Void) throws -> Self {
    guard parent.isFileURL else { throw CraftError.invalid("Choose a local destination folder.") }
    let staging = parent.appendingPathComponent(".photato-image-processor-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    do {
      for index in names.indices {
        try Task.checkCancellation()
        try write(index, staging.appendingPathComponent(String(index)))
      }
      return Self(staging: staging, names: names)
    } catch {
      try? FileManager.default.removeItem(at: staging)
      throw error
    }
  }
  func discard() {try? FileManager.default.removeItem(at:staging)}
  func commit(to parent: URL,validate: () throws -> Void = {}) throws -> [String] {
    let root = open(parent.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
    guard root >= 0 else {throw CraftError.invalid("The output folder is unavailable or is a symbolic link.")}
    defer {close(root)}
    var directories: [String:Int32] = ["":root],madeDirectories: [String] = [],published: [(Int32,String)] = [],names: [String] = []
    defer {for (name,fd) in directories where !name.isEmpty {close(fd)}}
    do {
      for (index,name) in self.names.enumerated() {
        try Task.checkCancellation();try validate()
        let parts = name.split(separator:"/",omittingEmptySubsequences:false).map(String.init)
        guard (1...2).contains(parts.count),parts.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":" ) && !$0.contains("\0")}) else {throw CraftError.invalid("Unsafe processed filename.")}
        let folder = parts.count == 2 ? parts[0]:"",filename = parts.last!
        if directories[folder] == nil {
          if mkdirat(root,folder,0o755) == 0 {madeDirectories.append(folder)} else if errno != EEXIST {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
          let fd = openat(root,folder,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
          guard fd >= 0 else {throw CraftError.invalid("A format output folder is unavailable or is a symbolic link.")};directories[folder] = fd
        }
        let fd = directories[folder]!,url = URL(fileURLWithPath:filename),base = url.deletingPathExtension().lastPathComponent,ext = url.pathExtension
        var candidate = filename,suffix = 0
        while linkat(AT_FDCWD,staging.appendingPathComponent(String(index)).path,fd,candidate,0) != 0 {
          guard errno == EEXIST,suffix < 10_000 else {throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
          suffix += 1;candidate = base+"_\(suffix)"+(ext.isEmpty ? "":"."+ext)
          try Task.checkCancellation();try validate()
        }
        published.append((fd,candidate));names.append(folder.isEmpty ? candidate:folder+"/"+candidate)
      }
      return names
    } catch {
      for (fd,name) in published.reversed() {_ = unlinkat(fd,name,0)}
      for folder in madeDirectories.reversed() {_ = unlinkat(root,folder,AT_REMOVEDIR)}
      throw error
    }
  }
}
