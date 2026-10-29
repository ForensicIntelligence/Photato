import Foundation
import PhotoCraftCore

/// One serializer targets either API Data or a bounded file transaction.
final class PSDOutput {
  private(set) var data = Data()
  private let file: AtomicFileWriter?
  private let maximumBytes: Int
  var count: Int { file?.count ?? data.count }
  init(file: AtomicFileWriter? = nil, maximumBytes: Int = PSDCodec.maximumInputBytes) {
    self.file = file
    self.maximumBytes = maximumBytes
  }
  func append(_ bytes: Data) throws {
    try Task.checkCancellation()
    guard bytes.count <= maximumBytes - count else {
      throw CraftError.invalid("PSD export exceeds the file size budget.")
    }
    if let file { try file.append(bytes) } else { data.append(bytes) }
  }
  func n(_ value: Int, _ width: Int) throws {
    var w = PSDWriter()
    w.n(value, width)
    try append(w.data)
  }
  func text(_ value: String) throws { try append(Data(value.utf8)) }
  func section(_ bytes: Data, lengthBytes: Int = 4) throws {
    let mark = try reserveLength(lengthBytes)
    try append(bytes)
    try finishLength(mark, width: lengthBytes)
  }
  func reserveLength(_ width: Int) throws -> Int {
    guard width == 4 || width == 8 else { throw CraftError.invalid("Invalid PSD length width.") }
    let mark = count
    try n(0, width)
    return mark
  }
  func patchLength(_ value: Int, at offset: Int, width: Int) throws {
    guard value >= 0, [2, 4, 8].contains(width),
      width != 2 || value <= Int(UInt16.max),
      width == 8 || UInt64(value) <= UInt64(UInt32.max),
      offset >= 0, offset <= count, width <= count - offset
    else { throw CraftError.invalid("PSD output length is out of range.") }
    var w = PSDWriter()
    w.n(value, width)
    if let file {
      try file.patch(w.data, at: offset)
    } else {
      data.replaceSubrange(offset..<offset + width, with: w.data)
    }
  }
  func finishLength(_ mark: Int, width: Int) throws {
    guard mark >= 0, mark <= count, width <= count - mark else {
      throw CraftError.invalid("Invalid PSD section boundary.")
    }
    try patchLength(count - mark - width, at: mark, width: width)
  }
}
