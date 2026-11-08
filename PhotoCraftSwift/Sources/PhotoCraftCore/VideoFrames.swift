import Foundation

/// Logical frame indexing with copy-on-write samples. Blank footage retains one
/// transparent prototype and only frames that have actually been edited.
public struct VideoFrames:RandomAccessCollection,MutableCollection,ExpressibleByArrayLiteral,Codable,Equatable,Sendable {
  public typealias Index=Int
  public static let maximumLogicalFrames=20_736_001
  public static let maximumOverrides=1_000_000
  private enum Storage:Equatable,Sendable {
    case sampled([Surface])
    case uniform(Surface,count:Int,edits:[Int:Surface])
  }
  private var storage:Storage
  public init(_ frames:[Surface]){storage = .sampled(frames)}
  public init(arrayLiteral elements:Surface...){self.init(elements)}
  public init(repeating prototype:Surface,count:Int)throws {
    guard (1...Self.maximumLogicalFrames).contains(count)else{throw CraftError.invalid("Invalid logical video frame count.")}
    storage = .uniform(prototype,count:count,edits:[:])
  }
  public var startIndex:Int {0}
  public var endIndex:Int {switch storage{case .sampled(let frames):frames.count;case .uniform(_,let count,_):count}}
  public var isSparse:Bool {if case .uniform=storage{return true};return false}
  /// Physical samples only: use for validation, memory accounting and archiving,
  /// never for enumerating playback positions.
  public var storedSurfaces:[Surface] {
    switch storage {
    case .sampled(let frames):return frames
    case .uniform(let prototype,_,let edits):return [prototype]+edits.keys.sorted().map{edits[$0]!}
    }
  }
  public var storedFrameCount:Int {switch storage{case .sampled(let frames):frames.count;case .uniform(_,_,let edits):edits.count+1}}
  public var estimatedBytes:Int {storedSurfaces.reduce(128+storedFrameCount*128){$0+$1.allocatedBytes}}
  public subscript(position:Int)->Surface {
    get {
      precondition(indices.contains(position))
      switch storage{case .sampled(let frames):return frames[position];case .uniform(let prototype,_,let edits):return edits[position] ?? prototype}
    }
    set {
      precondition(indices.contains(position))
      switch storage {
      case .sampled(var frames):frames[position]=newValue;storage = .sampled(frames)
      case .uniform(let prototype,let count,var edits):
        if newValue==prototype{edits.removeValue(forKey:position)}else{edits[position]=newValue}
        storage = .uniform(prototype,count:count,edits:edits)
      }
    }
  }
  public func validate()throws {
    switch storage {
    case .sampled(let frames):
      guard frames.count<=VideoClip.maximumFrames else{throw CraftError.invalid("Too many decoded source frames.")}
    case .uniform(_,let count,let edits):
      guard (1...Self.maximumLogicalFrames).contains(count),edits.count<=Self.maximumOverrides,
        edits.keys.allSatisfy({(0..<count).contains($0)})else{throw CraftError.invalid("Invalid sparse video frame storage.")}
    }
  }
  public static func ==(a:Self,b:Self)->Bool {
    guard a.count==b.count else{return false}
    if case .uniform(let x,_,let left)=a.storage,case .uniform(let y,_,let right)=b.storage {
      let changed=Set(left.keys).union(right.keys)
      if x != y && changed.count<a.count{return false}
      return changed.allSatisfy{a[$0]==b[$0]}
    }
    return a.elementsEqual(b)
  }
  private enum CodingKeys:CodingKey {case version,count,prototype,edits}
  private struct Edit:Codable {let index:Int,surface:Surface}
  public init(from decoder:Decoder)throws {
    if var values=try? decoder.unkeyedContainer() {
      guard values.count.map({$0<=VideoClip.maximumFrames}) ?? true else{throw CraftError.invalid("Too many decoded source frames.")}
      var frames:[Surface]=[]
      while !values.isAtEnd {
        guard frames.count<VideoClip.maximumFrames else{throw CraftError.invalid("Too many decoded source frames.")}
        frames.append(try values.decode(Surface.self))
      }
      storage = .sampled(frames);return
    }
    let fields=try decoder.container(keyedBy:CodingKeys.self)
    guard try fields.decode(Int.self,forKey:.version)==1 else{throw CraftError.invalid("Unsupported sparse video frame storage.")}
    let count=try fields.decode(Int.self,forKey:.count)
    guard (1...Self.maximumLogicalFrames).contains(count)else{throw CraftError.invalid("Invalid logical video frame count.")}
    let prototype=try fields.decode(Surface.self,forKey:.prototype)
    var values=try fields.nestedUnkeyedContainer(forKey:.edits)
    guard values.count.map({$0<=Self.maximumOverrides}) ?? true else{throw CraftError.invalid("Too many edited video frames.")}
    var edits:[Int:Surface]=[:],seen=Set<Int>()
    while !values.isAtEnd {
      guard seen.count<Self.maximumOverrides else{throw CraftError.invalid("Too many edited video frames.")}
      let edit=try values.decode(Edit.self)
      guard (0..<count).contains(edit.index),seen.insert(edit.index).inserted else{throw CraftError.invalid("Invalid or duplicate edited video frame.")}
      if edit.surface != prototype{edits[edit.index]=edit.surface}
    }
    storage = .uniform(prototype,count:count,edits:edits)
  }
  public func encode(to encoder:Encoder)throws {
    try validate()
    switch storage {
    case .sampled(let frames):
      var values=encoder.unkeyedContainer();for frame in frames{try values.encode(frame)}
    case .uniform(let prototype,let count,let edits):
      var fields=encoder.container(keyedBy:CodingKeys.self)
      try fields.encode(1,forKey:.version);try fields.encode(count,forKey:.count);try fields.encode(prototype,forKey:.prototype)
      var values=fields.nestedUnkeyedContainer(forKey:.edits)
      for index in edits.keys.sorted(){try Task.checkCancellation();try values.encode(Edit(index:index,surface:edits[index]!))}
    }
  }
}

extension CraftDocument {
  var requiresSparseVideoArchive:Bool {
    if layers.contains(where:{$0.video?.frames.isSparse==true}){return true}
    if animation?.retainedVideoSource?.layers.contains(where:{$0.video?.frames.isSparse==true})==true{return true}
    return videoTimeline?.retainedFrameSources?.contains(where:{$0.layers.contains(where:{$0.video?.frames.isSparse==true})})==true
  }
}
