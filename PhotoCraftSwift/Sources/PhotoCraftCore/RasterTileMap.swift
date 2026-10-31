import Foundation

/// A bounded direct working set, or an immutable mapped base and persistent edits.
/// Large-surface mutation copies at most four bounded tree nodes; ordinary tile
/// Array COW promotes only touched samples. Direct storage is capped at16,384 tiles.
struct RasterTileMap: Sendable, Equatable, Sequence, ExpressibleByDictionaryLiteral {
  static let directLimit=16_384
  struct Entry: Sendable { var tile: RasterTile? }
  private struct Stats: Equatable, Sendable {
    var entries=0,tiles=0,owned=0,mapped=0,invalid=0,nodes=0
    static func tile(_ tile: RasterTile?) -> Self {
      guard let tile else {return .init()}
      return .init(tiles:1,owned:tile.residentBytes,mapped:tile.isBacked ? 1:0,invalid:tile.count==TileArchive.pixelCount ? 0:1)
    }
    static func + (a: Self,b: Self) -> Self {.init(entries:a.entries+b.entries,tiles:a.tiles+b.tiles,owned:a.owned+b.owned,mapped:a.mapped+b.mapped,invalid:a.invalid+b.invalid,nodes:a.nodes+b.nodes)}
    static func - (a: Self,b: Self) -> Self {.init(entries:a.entries-b.entries,tiles:a.tiles-b.tiles,owned:a.owned-b.owned,mapped:a.mapped-b.mapped,invalid:a.invalid-b.invalid,nodes:a.nodes-b.nodes)}
  }
  private final class Node: @unchecked Sendable {
    var children:[UInt8:Node]=[:],values:[UInt8:Entry]=[:]
    var stats=Stats(nodes:1)
    // Only the root uses aggregate. Keep these cached counters behind COW
    // instead of inflating every Surface/Layer/Command value on worker stacks.
    var aggregate=Stats()
    func copy() -> Node {let n=Node();n.children=children;n.values=values;n.stats=stats;n.aggregate=aggregate;return n}
    func entry(_ key: Int,_ shift: Int) -> Entry? {
      let part=UInt8(truncatingIfNeeded:key>>shift)
      return shift==0 ? values[part]:children[part]?.entry(key,shift-8)
    }
    private func child(_ part: UInt8) {
      if children[part]==nil {children[part]=Node()}
      if !isKnownUniquelyReferenced(&children[part]!) {children[part]=children[part]!.copy()}
    }
    func set(_ key: Int,_ shift: Int,_ entry: Entry?) {
      let part=UInt8(truncatingIfNeeded:key>>shift)
      if shift==0 {
        let before=Stats.tile(values[part]?.tile)+Stats(entries:values[part]==nil ? 0:1)
        values[part]=entry
        let after=Stats.tile(entry?.tile)+Stats(entries:entry==nil ? 0:1)
        stats=stats+after-before
      } else {
        if entry==nil && children[part]==nil {return}
        let existed=children[part] != nil
        child(part);let before=existed ? children[part]!.stats:Stats()
        children[part]!.set(key,shift-8,entry)
        let after=children[part]!.stats.entries==0 ? Stats():children[part]!.stats;stats=stats+after-before
        if after.entries==0 {children[part]=nil}
      }
    }
    func mutableChild(_ part: UInt8) -> Node {child(part);return children[part]!}
    func maximumKey(prefix: Int=0,shift: Int=24) -> Int {
      if shift==0 {return values.keys.max().map{prefix|Int($0)} ?? -1}
      guard let part=children.keys.max() else {return -1}
      return children[part]!.maximumKey(prefix:prefix|(Int(part)<<shift),shift:shift-8)
    }
    func history(_ seen: inout Set<UInt>) -> Int {
      guard seen.insert(UInt(bitPattern:ObjectIdentifier(self))).inserted else {return 0}
      if stats.entries==0 {return 0}
      var bytes=256+values.count*96
      for child in children.values {bytes+=child.history(&seen)}
      for entry in values.values {
        if let tile=entry.tile,!tile.isBacked,seen.insert(tile.identity).inserted {bytes+=tile.residentBytes}
      }
      return bytes
    }
    func pathIDs(_ key: Int,shift: Int=24) -> [UInt] {
      [UInt(bitPattern:ObjectIdentifier(self))]+(shift>0 ? children[UInt8(truncatingIfNeeded:key>>shift)]?.pathIDs(key,shift:shift-8) ?? []:[])
    }
  }
  private static let emptyRoot=Node()
  private var root=RasterTileMap.emptyRoot
  private var base:RuntimeTileIndex?
  private var direct:Bool {base==nil && root === Self.emptyRoot}
  private var small:[Int:RasterTile]=[:]
  private var total:Stats {
    get {root.aggregate}
    set {makeMutable();root.aggregate=newValue}
  }
  init(persistent:Bool=false) {if persistent {root=Node()}}
  init(dictionaryLiteral elements:(Int,RasterTile)...) {for (key,tile) in elements {self[key]=tile}}
  init(base: RuntimeTileIndex) {self.base=base;root=Node();root.aggregate = .init(tiles:base.count,mapped:base.count)}
  var count: Int {direct ? small.count:total.tiles}
  var residentIndexBytes: Int {direct ? small.values.reduce(0){$0+($1.isBacked ? 128:0)}:(root.stats.entries==0 ? 0:root.stats.nodes*256+root.stats.entries*96)+(base?.residentEstimate ?? 0)}
  var residentBytes: Int {direct ? small.values.reduce(0){$0+$1.residentBytes+($1.isBacked ? 128:0)}:total.owned+residentIndexBytes}
  var mappedTileCount: Int {direct ? small.values.reduce(0){$0+($1.isBacked ? 1:0)}:total.mapped}
  var mappedIndexBytes: Int {base?.mappedBytes ?? 0}
  var editEntryCount: Int {direct ? small.count:root.stats.entries}
  func isStructurallyValid(maximumKey: Int) -> Bool {
    if direct {return small.allSatisfy{$0.key>=0 && $0.key<maximumKey && $0.value.count==TileArchive.pixelCount}}
    return total.invalid==0 && Swift.max(base?.maximumKey ?? -1,root.maximumKey())<maximumKey
  }
  private mutating func makeMutable() {if !isKnownUniquelyReferenced(&root) {root=root.copy()}}
  private mutating func transitionToTree() {
    guard direct else{return};makeMutable()
    for (key,tile) in small {root.set(key,24,Entry(tile:tile))}
    total=Stats(tiles:root.stats.tiles,owned:root.stats.owned,mapped:root.stats.mapped,invalid:root.stats.invalid)
    small=[:]
  }
  // Return trivial samples across the paged ownership boundary. Keeping the
  // bounded Dictionary path visible to the optimizer avoids coroutine/retain
  // work per pixel without expanding radix ownership into throwing kernels.
  @inline(__always)
  func pixel(key:Int,offset:Int,default fallback:Pixel) -> Pixel {
    if direct {return small[key]?[offset] ?? fallback}
    return pagedPixel(key:key,offset:offset,default:fallback)
  }
  @inline(never)
  private func pagedPixel(key:Int,offset:Int,default fallback:Pixel) -> Pixel {
    self[key]?[offset] ?? fallback
  }
  @inline(__always)
  mutating func setPixel(key:Int,offset:Int,pixel:Pixel,default fallback:Pixel) {
    if direct && (small.count<Self.directLimit || small[key] != nil) {
      small[key,default:RasterTile(repeating:fallback,count:TileArchive.pixelCount)][offset]=pixel
      return
    }
    setPagedPixel(key:key,offset:offset,pixel:pixel,default:fallback)
  }
  @inline(never)
  private mutating func setPagedPixel(key:Int,offset:Int,pixel:Pixel,default fallback:Pixel) {
    self[key,default:RasterTile(repeating:fallback,count:TileArchive.pixelCount)][offset]=pixel
  }
  subscript(key: Int) -> RasterTile? {
    get {
      if direct {return small[key]}
      if let entry=root.entry(key,24) {return entry.tile}
      return base?.tile(for:key)
    }
    set {
      precondition(key>=0 && key<RuntimeTileIndex.maximumEntries)
      if direct {
        if small.count>=Self.directLimit && small[key]==nil && newValue != nil {transitionToTree()}
        else {small[key]=newValue;return}
      }
      let before=Stats.tile(self[key]),after=Stats.tile(newValue)
      if before.tiles==0 && after.tiles==0 {return}
      makeMutable()
      let entry:Entry? = newValue != nil || base?.tile(for:key) != nil ? Entry(tile:newValue):nil
      root.set(key,24,entry);total=total+after-before
    }
  }
  private func prepareLeaf(_ leaf: Node,_ part: UInt8,_ key: Int,_ defaultValue: () -> RasterTile) {
    if leaf.values[part]?.tile == nil {
      let initial=leaf.values[part]==nil ? base?.tile(for:key) ?? defaultValue():defaultValue()
      leaf.values[part]=Entry(tile:initial)
    }
  }
  subscript(key: Int,default defaultValue: @autoclosure () -> RasterTile) -> RasterTile {
    get {self[key] ?? defaultValue()}
    _modify {
      precondition(key>=0 && key<RuntimeTileIndex.maximumEntries)
      if direct {
        if small.count>=Self.directLimit && small[key]==nil {transitionToTree()}
        else {yield &small[key,default:defaultValue()];return}
      }
      makeMutable()
      let pa=UInt8(truncatingIfNeeded:key>>24),pb=UInt8(truncatingIfNeeded:key>>16),pc=UInt8(truncatingIfNeeded:key>>8)
      let ca=root.children[pa]==nil;let a=root.mutableChild(pa)
      let cb=a.children[pb]==nil;let b=a.mutableChild(pb)
      let cc=b.children[pc]==nil;let leaf=b.mutableChild(pc),part=UInt8(truncatingIfNeeded:key)
      let existed=leaf.values[part] != nil
      let before=Stats.tile(existed ? leaf.values[part]?.tile:base?.tile(for:key))
      let prior=Stats.tile(leaf.values[part]?.tile)+Stats(entries:existed ? 1:0)
      prepareLeaf(leaf,part,key,defaultValue)
      yield &leaf.values[part]!.tile!
      let after=Stats.tile(leaf.values[part]?.tile),delta=after+Stats(entries:1)-prior
      if delta != Stats() {
        leaf.stats=leaf.stats+delta;b.stats=b.stats+delta+Stats(nodes:cc ? 1:0)
        a.stats=a.stats+delta+Stats(nodes:(cb ? 1:0)+(cc ? 1:0))
        root.stats=root.stats+delta+Stats(nodes:(ca ? 1:0)+(cb ? 1:0)+(cc ? 1:0))
      }
      if before != after {total=total+after-before}
    }
  }
  var keys: LazyMapSequence<RasterTileMap,Int> {lazy.map(\.0)}
  var values: LazyMapSequence<RasterTileMap,RasterTile> {lazy.map(\.1)}
  func accountHistory(_ seen: inout Set<UInt>) -> Int {
    if direct {
      var bytes=0
      for tile in small.values where seen.insert(tile.identity).inserted {bytes+=tile.isBacked ? 128:tile.residentBytes}
      return bytes
    }
    var bytes=0
    if let base,seen.insert(UInt(bitPattern:ObjectIdentifier(base))).inserted {bytes+=base.residentEstimate}
    return bytes+root.history(&seen)
  }
  func editPathIDs(for key: Int) -> [UInt] {root.pathIDs(key)}

  private struct TreeIterator: IteratorProtocol {
    struct Frame {let node:Node;let prefix:Int;let shift:Int;let keys:[UInt8];var next=0}
    var stack:[Frame]=[]
    let lower:Int,upper:Int
    init(_ root: Node,lower: Int,upper: Int) {self.lower=lower;self.upper=upper;push(root,0,24)}
    mutating func push(_ node:Node,_ prefix:Int,_ shift:Int) {
      let keys=(shift==0 ? Array(node.values.keys):Array(node.children.keys)).filter {part in
        let first=prefix|(Int(part)<<shift),last=first+(1<<shift)
        return first<upper && last>lower
      }.sorted()
      stack.append(.init(node:node,prefix:prefix,shift:shift,keys:keys))
    }
    mutating func next() -> (Int,Entry)? {
      while !stack.isEmpty {
        let i=stack.count-1
        if stack[i].next==stack[i].keys.count {stack.removeLast();continue}
        let part=stack[i].keys[stack[i].next];stack[i].next+=1
        let key=stack[i].prefix|(Int(part)<<stack[i].shift)
        if stack[i].shift==0 {return (key,stack[i].node.values[part]!)}
        push(stack[i].node.children[part]!,key,stack[i].shift-8)
      }
      return nil
    }
  }
  struct Iterator: IteratorProtocol {
    private let base:RuntimeTileIndex?
    private var position:Int
    private let upper:Int
    private var edits:TreeIterator
    private var edit:(Int,Entry)?
    private var directStore:[Int:RasterTile]?
    private var directKeys:IndexingIterator<[Int]>?
    fileprivate init(_ map:RasterTileMap,lower:Int,upper:Int) {
      base=map.base;position=map.base?.lowerBound(lower) ?? 0;self.upper=upper
      edits=TreeIterator(map.root,lower:lower,upper:upper);edit=edits.next()
      if map.direct {
        directStore=map.small
        directKeys=map.small.keys.filter{$0>=lower && $0<upper}.sorted().makeIterator()
      }
    }
    mutating func next() -> (Int,RasterTile)? {
      if directKeys != nil {guard let key=directKeys!.next() else{return nil};return (key,directStore![key]!)}
      while true {
        let key=position<(base?.count ?? 0) ? base!.key(at:position):Int.max
        let baseKey=key<upper ? key:Int.max
        if let current=edit,current.0<=baseKey {
          if current.0==baseKey {position+=1};edit=edits.next()
          if let tile=current.1.tile {return (current.0,tile)}
        } else if baseKey != Int.max {
          let tile=base!.tile(at:position);position+=1;return (baseKey,tile)
        } else {return nil}
      }
    }
  }
  func makeIterator() -> Iterator {Iterator(self,lower:0,upper:Int.max)}
  struct RangeSequence: Sequence {
    let map:RasterTileMap,lower:Int,upper:Int
    func makeIterator() -> Iterator {Iterator(map,lower:lower,upper:upper)}
  }
  func entries(in range:Range<Int>) -> RangeSequence {.init(map:self,lower:range.lowerBound,upper:range.upperBound)}

  private struct DifferenceIterator: IteratorProtocol {
    struct Frame {let a:Node?;let b:Node?;let prefix:Int;let shift:Int;let keys:[UInt8];var next=0}
    var stack:[Frame]=[]
    init(_ a:Node,_ b:Node) {push(a,b,0,24)}
    mutating func push(_ a:Node?,_ b:Node?,_ prefix:Int,_ shift:Int) {
      if a === b {return}
      let left=shift==0 ? Array(a?.values.keys ?? [:].keys):Array(a?.children.keys ?? [:].keys)
      let right=shift==0 ? Array(b?.values.keys ?? [:].keys):Array(b?.children.keys ?? [:].keys)
      stack.append(.init(a:a,b:b,prefix:prefix,shift:shift,keys:Set(left).union(right).sorted()))
    }
    mutating func next() -> Int? {
      while !stack.isEmpty {
        let i=stack.count-1
        if stack[i].next==stack[i].keys.count {stack.removeLast();continue}
        let part=stack[i].keys[stack[i].next];stack[i].next+=1
        let key=stack[i].prefix|(Int(part)<<stack[i].shift)
        if stack[i].shift==0 {return key}
        push(stack[i].a?.children[part],stack[i].b?.children[part],key,stack[i].shift-8)
      }
      return nil
    }
  }
  struct KeyUnion: Sequence,IteratorProtocol {
    private var a:Iterator,b:Iterator
    private var left:(Int,RasterTile)?,right:(Int,RasterTile)?
    fileprivate init(_ a:RasterTileMap,_ b:RasterTileMap) {
      self.a=a.makeIterator();self.b=b.makeIterator();left=self.a.next();right=self.b.next()
    }
    mutating func next() -> Int? {
      guard left != nil || right != nil else {return nil}
      let l=left?.0 ?? Int.max,r=right?.0 ?? Int.max,key=Swift.min(l,r)
      if l==key {left=a.next()};if r==key {right=b.next()};return key
    }
  }
  struct CandidateKeys: Sequence,IteratorProtocol {
    private var difference:DifferenceIterator?
    private var union:KeyUnion?
    fileprivate init(_ a:RasterTileMap,_ b:RasterTileMap) {
      if !a.direct && !b.direct && a.base === b.base {difference=DifferenceIterator(a.root,b.root)}else{union=KeyUnion(a,b)}
    }
    mutating func next() -> Int? {if difference != nil {return difference!.next()};return union!.next()}
  }
  func unionKeys(with other:Self) -> KeyUnion {KeyUnion(self,other)}
  func candidateKeys(comparedTo other:Self) -> CandidateKeys {CandidateKeys(self,other)}
  static func == (a:Self,b:Self) -> Bool {
    guard a.count==b.count else{return false}
    if a.direct && b.direct {return a.small==b.small}
    for key in a.candidateKeys(comparedTo:b) where a[key] != b[key] {return false}
    return true
  }
}
