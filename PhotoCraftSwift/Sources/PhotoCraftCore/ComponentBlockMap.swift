import Foundation

/// Persistent edit overlay: at most four 256-way nodes are copied per new
/// mutation. Immutable mapped samples need no resident per-block descriptor.
struct ComponentBlockMap: Sendable, Sequence {
  fileprivate final class Node: @unchecked Sendable {
    var children: [UInt8: Node] = [:]
    var values: [UInt8: ComponentBlock] = [:]
    func copy() -> Node { let n = Node(); n.children = children; n.values = values; return n }
    func value(_ key: Int, shift: Int) -> ComponentBlock? {
      let part = UInt8(truncatingIfNeeded: key >> shift)
      return shift == 0 ? values[part] : children[part]?.value(key, shift: shift - 8)
    }
    func set(_ key: Int, shift: Int, value: ComponentBlock) {
      let part = UInt8(truncatingIfNeeded: key >> shift)
      if shift == 0 { values[part] = value; return }
      if children[part] == nil { children[part] = Node() }
      if !isKnownUniquelyReferenced(&children[part]!) { children[part] = children[part]!.copy() }
      children[part]!.set(key, shift: shift - 8, value: value)
    }
    func modify(_ key: Int, shift: Int, offset: Int, word: UInt32, stride: Int) {
      let part = UInt8(truncatingIfNeeded: key >> shift)
      if shift == 0 { values[part]!.set(word, offset: offset, stride: stride); return }
      if !isKnownUniquelyReferenced(&children[part]!) { children[part] = children[part]!.copy() }
      children[part]!.modify(key, shift: shift - 8, offset: offset, word: word, stride: stride)
    }
    var residentBytes: Int { 256 + values.values.reduce(0) { $0 + 96 + $1.residentBytes } + children.values.reduce(0) { $0 + $1.residentBytes } }
  }
  private var root: Node?
  var residentBytes: Int { root?.residentBytes ?? 0 }
  func sharesRoot(with other: Self) -> Bool { root === other.root }
  subscript(key: Int) -> ComponentBlock? {
    get { root?.value(key, shift: 24) }
    set {
      precondition(key >= 0 && key <= Int(UInt32.max) && newValue != nil)
      makeMutable(); root!.set(key, shift: 24, value: newValue!)
    }
  }
  private mutating func makeMutable() {
    if root == nil { root = Node() }
    else if !isKnownUniquelyReferenced(&root) { root = root!.copy() }
  }
  mutating func modify(_ key: Int, offset: Int, word: UInt32, stride: Int) {
    makeMutable(); root!.modify(key, shift: 24, offset: offset, word: word, stride: stride)
  }
  struct Iterator: IteratorProtocol {
    fileprivate struct Frame { var node: Node; var keys: [UInt8]; var cursor: Int; var prefix: Int; var shift: Int }
    fileprivate var stack: [Frame]
    mutating func next() -> (Int, ComponentBlock)? {
      while !stack.isEmpty {
        let i = stack.count - 1
        if stack[i].cursor == stack[i].keys.count { stack.removeLast(); continue }
        let f = stack[i], part = f.keys[f.cursor]; stack[i].cursor += 1
        let key = f.prefix | (Int(part) << f.shift)
        if f.shift == 0 { return (key, f.node.values[part]!) }
        let child = f.node.children[part]!, shift = f.shift - 8
        stack.append(Frame(node: child, keys: shift == 0 ? child.values.keys.sorted() : child.children.keys.sorted(), cursor: 0, prefix: key, shift: shift))
      }
      return nil
    }
  }
  func makeIterator() -> Iterator {
    Iterator(stack: root.map { [Iterator.Frame(node: $0, keys: $0.children.keys.sorted(), cursor: 0, prefix: 0, shift: 24)] } ?? [])
  }
}
