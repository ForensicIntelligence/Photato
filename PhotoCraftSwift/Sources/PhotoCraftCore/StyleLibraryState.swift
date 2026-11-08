import Foundation

public struct StyleLibraryNode: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var parentID: UUID?
  public var name: String
  public var preset: StylePreset?
  public var isGroup: Bool {preset==nil}
  public init(id:UUID=UUID(),parentID:UUID?=nil,name:String,preset:StylePreset?=nil) {self.id=id;self.parentID=parentID;self.name=name;self.preset=preset}
}
public enum StyleLibraryMutation: Sendable {
  case save(String,StylePreset,parent:UUID?)
  case group(String,parent:UUID?)
  case rename(UUID,String)
  case move(Set<UUID>,parent:UUID?,before:UUID?)
  case duplicate(Set<UUID>,parent:UUID?,before:UUID?)
  case delete(Set<UUID>)
}
public struct StyleLibraryState: Codable, Equatable, Sendable {
  public static let maximumNodes=4096
  public static let maximumDepth=64
  public static let maximumBytes=512*1024*1024
  public var nodes:[StyleLibraryNode]=[]
  public init(nodes:[StyleLibraryNode]=[]) {self.nodes=nodes}
  public func node(_ id:UUID)->StyleLibraryNode? {nodes.first{$0.id==id}}
  public func descendants(_ id:UUID)->Set<UUID> {
    var found=Set<UUID>(),pending=[id]
    while let value=pending.popLast(),found.count<=Self.maximumNodes {if found.insert(value).inserted {pending.append(contentsOf:nodes.filter{$0.parentID==value}.map(\.id))}}
    return found
  }
  public func ordered() throws -> [StyleLibraryNode] {
    guard nodes.count<=Self.maximumNodes,Set(nodes.map(\.id)).count==nodes.count else {throw CraftError.invalid("Invalid style library identifiers or count.")}
    let byID=Dictionary(uniqueKeysWithValues:nodes.map{($0.id,$0)})
    for item in nodes {if let parent=item.parentID {guard parent != item.id,byID[parent]?.isGroup==true else {throw CraftError.invalid("Style group parent is missing or is not a group.")}}}
    let groups=Dictionary(grouping:nodes,by:\.parentID)
    var pending=(groups[nil] ?? []).reversed().map{($0,0)},result=[StyleLibraryNode]()
    while let (node,depth)=pending.popLast() {
      try Task.checkCancellation()
      guard depth<=Self.maximumDepth,!node.isGroup || depth<Self.maximumDepth else {throw CraftError.invalid("Style groups are too deeply nested.")}
      result.append(node);pending.append(contentsOf:(groups[node.id] ?? []).reversed().map{($0,depth+1)})
    }
    guard result.count==nodes.count else {throw CraftError.invalid("Style groups contain a cycle.")};return result
  }
  public static func validateName(_ name:String) throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=65535 else {throw CraftError.invalid("Enter a nonempty style or group name of at most 65,535 UTF-16 units.")}
  }
  public func validate() throws {
    _=try ordered();var total=0
    for node in nodes {
      try Self.validateName(node.name);try node.preset?.validate()
      for pattern in node.preset?.patterns ?? [] {let count=pattern.surface.width*pattern.surface.height;guard count<=64_000_000-total else {throw CraftError.invalid("Style library pattern resources exceed the working budget.")};total+=count}
    }
  }
  private mutating func insert(_ values:[StyleLibraryNode],roots:Set<UUID>,parent:UUID?,before:UUID?) throws {
    if let parent {guard node(parent)?.isGroup==true else {throw CraftError.invalid("Choose an existing style group.")}}
    if let before {guard let item=node(before),item.parentID==parent else {throw CraftError.invalid("Style insertion target changed.")}}
    var values=values;for i in values.indices where roots.contains(values[i].id) {values[i].parentID=parent}
    let index:Int
    if let before {index=nodes.firstIndex{$0.id==before}!}
    else if let parent {let family=descendants(parent);index=(nodes.lastIndex{family.contains($0.id)} ?? nodes.count-1)+1}
    else {index=nodes.count}
    nodes.insert(contentsOf:values,at:index);nodes=try ordered()
  }
  @discardableResult public mutating func apply(_ mutation:StyleLibraryMutation) throws -> UUID? {
    try validate();var next=self;var created:UUID?
    switch mutation {
    case .save(let name,let preset,let parent):
      let node=StyleLibraryNode(name:name,preset:preset);created=node.id;try next.insert([node],roots:[node.id],parent:parent,before:nil)
    case .group(let name,let parent):
      let node=StyleLibraryNode(name:name);created=node.id;try next.insert([node],roots:[node.id],parent:parent,before:nil)
    case .rename(let id,let name):
      guard let i=next.nodes.firstIndex(where:{$0.id==id}) else {throw CraftError.invalid("Style entry no longer exists.")};next.nodes[i].name=name
    case .move(let ids,let parent,let before),.duplicate(let ids,let parent,let before):
      guard !ids.isEmpty,ids.isSubset(of:Set(nodes.map(\.id))) else {throw CraftError.invalid("Choose existing style entries.")}
      let roots=try ordered().filter {item in
        guard ids.contains(item.id) else{return false};var p=item.parentID
        while let value=p {if ids.contains(value){return false};p=node(value)?.parentID};return true
      }
      let family=roots.reduce(into:Set<UUID>()){$0.formUnion(descendants($1.id))}
      if case .move=mutation {guard parent.map({!family.contains($0)}) ?? true,before.map({!family.contains($0)}) ?? true else {throw CraftError.invalid("Cannot insert styles into their own subtree.")}}
      var incoming=try ordered().filter{family.contains($0.id)};var rootIDs=Set(roots.map(\.id))
      if case .duplicate=mutation {
        let mapping=Dictionary(uniqueKeysWithValues:incoming.map{($0.id,UUID())})
        for i in incoming.indices {let old=incoming[i].id;incoming[i].id=mapping[old]!;incoming[i].parentID=incoming[i].parentID.flatMap{mapping[$0] ?? $0}}
        rootIDs=Set(roots.map{mapping[$0.id]!});created=rootIDs.sorted{$0.uuidString<$1.uuidString}.first
      } else {next.nodes.removeAll{family.contains($0.id)}}
      try next.insert(incoming,roots:rootIDs,parent:parent,before:before)
    case .delete(let ids):
      guard !ids.isEmpty,ids.isSubset(of:Set(nodes.map(\.id))) else {throw CraftError.invalid("Choose existing styles to delete.")}
      let family=ids.reduce(into:Set<UUID>()){$0.formUnion(descendants($1))};next.nodes.removeAll{family.contains($0.id)}
    }
    try next.validate();self=next;return created
  }
  private struct Envelope:Codable {var kind="PhotatoStyleLibrary";var version=1;var state:StyleLibraryState}
  public func encoded() throws -> Data {
    try validate();let encoder=PropertyListEncoder();encoder.outputFormat = .binary
    let data=try encoder.encode(Envelope(state:self));guard data.count<=Self.maximumBytes else {throw CraftError.invalid("Style library file is too large.")};return data
  }
  public static func decode(_ data:Data) throws -> Self {
    guard data.count<=maximumBytes else {throw CraftError.invalid("Style library file is too large.")}
    let decoder=PropertyListDecoder();decoder.userInfo[.rasterDecodeBudget]=RasterDecodeBudget(bytes:512*1024*1024)
    let envelope=try decoder.decode(Envelope.self,from:data)
    guard envelope.kind=="PhotatoStyleLibrary",envelope.version==1 else {throw CraftError.unsupported("Unsupported Photato style library. Adobe ASL is not supported yet.")}
    try envelope.state.validate();return envelope.state
  }
}
