import Foundation

/// A private mutable candidate with a bounded write-back cache. Publication is
/// immutable and atomic; cache size never grows with the logical component plane.
final class ComponentPlaneBuilder {
  private let plane: ComponentPlane
  private let maximumBytes: Int
  private let directory: URL?
  private let reserve: ((Int) throws -> Void)?
  private let capacity: Int
  private var writer: ComponentPlaneWriter?
  private struct Entry { var block: ComponentBlock; var dirty: Bool }
  private var cache: [Int: Entry] = [:]
  private var order: [Int] = []
  private(set) var maximumCachedBlocks = 0
  private var failed = false
  private var finished = false
  init(plane: ComponentPlane, maximumBytes: Int = RasterTileStore.defaultMaximumBytes,
    directory: URL? = nil, cacheBlocks: Int = 64, reserve: ((Int) throws -> Void)? = nil) throws {
    guard (0...RasterTileStore.defaultMaximumBytes).contains(maximumBytes), (1...64).contains(cacheBlocks),
      (directory == nil || directory!.isFileURL), plane.storedBlockCount == 0 else { throw CraftError.invalid("Invalid component builder limits.") }
    self.plane=plane;self.maximumBytes=maximumBytes;self.directory=directory;self.capacity=cacheBlocks;self.reserve=reserve
  }
  func setWord(_ word: UInt32, at index: Int) throws {
    guard !failed, !finished else {throw CraftError.invalid("Component builder is unavailable.")}
    guard (0..<plane.count).contains(index) else {failed=true;throw CraftError.invalid("Component builder sample is outside its plane.")}
    do {
      try Task.checkCancellation();try ComponentPlane.validate(word:word,depth:plane.depth)
      let key=index/ComponentPlane.blockSamples,offset=index%ComponentPlane.blockSamples
      if cache[key] == nil {
        if word == plane.defaultWord && writer?.contains(key) != true {return}
        if cache.count == capacity {
          let old=order.removeFirst();try flush(old);cache.removeValue(forKey:old)
        }
        let block=try writer?.read(key:key) ?? ComponentBlock(fill:plane.defaultWord,stride:plane.sampleBytes)
        cache[key]=Entry(block:block,dirty:false);order.append(key);maximumCachedBlocks=max(maximumCachedBlocks,cache.count)
      }
      if cache[key]!.block.word(offset,stride:plane.sampleBytes) == word {return}
      cache[key]!.block.set(word,offset:offset,stride:plane.sampleBytes);cache[key]!.dirty=true
    } catch { failed=true;throw error }
  }
  private func flush(_ key: Int) throws {
    guard cache[key]?.dirty == true else {return}
    if writer == nil {writer=try ComponentPlaneWriter(plane:plane,maximumBytes:maximumBytes,directory:directory,reserve:reserve)}
    try writer!.write(key:key,block:cache[key]!.block)
    cache[key]!.dirty=false
  }
  func finish() throws -> ComponentPlane {
    guard !failed,!finished else {throw CraftError.invalid("Component builder cannot publish after completion or failure.")}
    do {
      try Task.checkCancellation()
      for key in order {try flush(key)}
      let result=try writer.map {plane.retaining(try $0.finish())} ?? plane
      finished=true;cache=[:];order=[];return result
    } catch {failed=true;throw error}
  }
}
