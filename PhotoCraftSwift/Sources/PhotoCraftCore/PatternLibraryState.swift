import Foundation

/// Flat, bounded hierarchy keeps native decoding independent of recursive payload depth.
public struct PatternLibraryNode: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var parentID: UUID?
  public var name: String
  public var patternID: String?
  public var isGroup: Bool { patternID == nil }
  public init(id: UUID = UUID(), parentID: UUID? = nil, name: String = "", patternID: String? = nil) {
    self.id=id; self.parentID=parentID; self.name=name; self.patternID=patternID
  }
}

public enum PatternLibraryMutation: Sendable {
  case select(Set<UUID>, active: UUID?)
  case createGroup(String, parent: UUID?)
  case rename(UUID, String)
  case move(Set<UUID>, parent: UUID?, before: UUID?)
  case duplicate(Set<UUID>, parent: UUID?, before: UUID?)
  case delete(Set<UUID>)
  case collapse(UUID, Bool)
}

public struct PatternLibraryState: Codable, Equatable, Sendable {
  public static let version = 2
  public static let maximumNodes = 4096
  public static let maximumDepth = 64
  public var patterns: [RasterPattern]
  public var nodes: [PatternLibraryNode]
  public var selectedID: String?
  public var selectedNodes: Set<UUID>
  public var activeNodeID: UUID?
  public var collapsed: Set<UUID>
  public init(patterns: [RasterPattern], selectedID: String? = nil, nodes: [PatternLibraryNode]? = nil) {
    let items=nodes ?? patterns.map { PatternLibraryNode(patternID:$0.id) }
    let selected=selectedID.flatMap { id in patterns.contains{$0.id==id} ? id:nil }
    let active=items.first(where:{$0.patternID==selected && selected != nil})?.id
    self.patterns=patterns;self.nodes=items;self.selectedID=selected
    activeNodeID=active;selectedNodes=Set(active.map{[$0]} ?? []);collapsed=[]
  }
  public func node(_ id: UUID) -> PatternLibraryNode? { nodes.first{$0.id==id} }
  public func name(_ id: UUID) -> String? {
    guard let item=node(id)else{return nil}
    return item.patternID.flatMap { id in patterns.first{$0.id==id}?.displayName } ?? item.name
  }
  public func children(of parent:UUID?) -> [PatternLibraryNode] { nodes.filter{$0.parentID==parent} }
  public func depth(of id:UUID) -> Int {
    var result=0,parent=node(id)?.parentID
    while let value=parent,result<=Self.maximumDepth {result+=1;parent=node(value)?.parentID}
    return result
  }
  public func descendants(of id:UUID) -> Set<UUID> {
    var found=Set<UUID>(),pending=[id]
    while let value=pending.popLast(),found.count<=Self.maximumNodes {
      guard found.insert(value).inserted else{continue}
      pending.append(contentsOf:nodes.filter{$0.parentID==value}.map(\.id))
    }
    return found
  }
  public func orderedNodes() throws -> [PatternLibraryNode] {
    guard nodes.count<=Self.maximumNodes,Set(nodes.map(\.id)).count==nodes.count else {
      throw CraftError.invalid("Invalid pattern group identifiers or library node budget.")
    }
    let byID=Dictionary(uniqueKeysWithValues:nodes.map{($0.id,$0)})
    for item in nodes {
      if let parent=item.parentID {
        guard parent != item.id,byID[parent]?.isGroup==true else {throw CraftError.invalid("Pattern group parent is missing or is not a group.")}
      }
    }
    let children=Dictionary(grouping:nodes,by:\.parentID)
    var pending=(children[nil] ?? []).reversed().map{($0,0)},result=[PatternLibraryNode]()
    while let (item,depth)=pending.popLast() {
      try Task.checkCancellation()
      guard depth<=Self.maximumDepth, !item.isGroup || depth<Self.maximumDepth else{throw CraftError.invalid("Pattern groups are too deeply nested.")}
      result.append(item)
      pending.append(contentsOf:(children[item.id] ?? []).reversed().map{($0,depth+1)})
    }
    guard result.count==nodes.count else{throw CraftError.invalid("Pattern groups contain a cycle.")}
    return result
  }
  public func validate() throws {
    try PatternArchive.validate(patterns)
    _=try orderedNodes()
    let assets=Set(patterns.map(\.id)),ids=Set(nodes.map(\.id)),groups=Set(nodes.filter(\.isGroup).map(\.id))
    var references=Set<String>(),leaves=0
    for item in nodes {
      if let id=item.patternID {
        guard assets.contains(id),item.name.isEmpty else{throw CraftError.invalid("Pattern node has an invalid asset reference.")}
        references.insert(id);leaves+=1
      }else{try Self.validateName(item.name)}
    }
    guard leaves<=PatternArchive.maxCount,references==assets,
      selectedID==nil || assets.contains(selectedID!),selectedNodes.isSubset(of:ids),collapsed.isSubset(of:groups),
      activeNodeID==nil || nodes.contains(where:{$0.id==activeNodeID && !$0.isGroup})
    else{throw CraftError.invalid("Pattern library references or selection are invalid.")}
  }
  public static func validateName(_ name:String)throws {
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf16.count<=65_535 else{
      throw CraftError.invalid("Enter a nonempty pattern or group name of at most65535UTF-16 units.")
    }
  }
  mutating func pruneSelection() {
    let ids=Set(nodes.map(\.id)),groups=Set(nodes.filter(\.isGroup).map(\.id))
    selectedNodes.formIntersection(ids);collapsed.formIntersection(groups)
    if let activeNodeID,!ids.contains(activeNodeID){self.activeNodeID=nil}
    if let selectedID,!patterns.contains(where:{$0.id==selectedID}){self.selectedID=patterns.first?.id}
  }
  func topmost(_ ids:Set<UUID>)throws->[PatternLibraryNode] {
    guard !ids.isEmpty,ids.isSubset(of:Set(nodes.map(\.id)))else{throw CraftError.invalid("Choose existing pattern presets or groups.")}
    return try orderedNodes().filter{item in
      guard ids.contains(item.id)else{return false}
      var parent=item.parentID
      while let value=parent{if ids.contains(value){return false};parent=node(value)?.parentID}
      return true
    }
  }
  mutating func insert(_ incoming:[PatternLibraryNode],roots:Set<UUID>,parent:UUID?,before:UUID?)throws {
    if let parent{guard node(parent)?.isGroup==true else{throw CraftError.invalid("Choose an existing pattern group.")}}
    if let before{guard node(before)?.parentID==parent,node(before) != nil else{throw CraftError.invalid("Pattern insertion target changed.")}}
    var values=incoming
    for i in values.indices where roots.contains(values[i].id){values[i].parentID=parent}
    let index:Int
    if let before{index=nodes.firstIndex{$0.id==before}!}
    else if let parent{let ids=descendants(of:parent);index=(nodes.lastIndex{ids.contains($0.id)} ?? nodes.count-1)+1}
    else{index=nodes.count}
    nodes.insert(contentsOf:values,at:index);nodes=try orderedNodes()
  }
  @discardableResult public mutating func apply(_ mutation:PatternLibraryMutation)throws->UUID? {
    try validate();var next=self;var created:UUID?
    switch mutation {
    case .select(let ids,let active):
      guard ids.isSubset(of:Set(nodes.map(\.id))),active==nil || ids.contains(active!),
        active==nil || node(active!)?.patternID != nil else{throw CraftError.invalid("Invalid pattern selection.")}
      next.selectedNodes=ids;next.activeNodeID=active
      if let active{next.selectedID=node(active)?.patternID}
    case .createGroup(let name,let parent):
      try Self.validateName(name);let item=PatternLibraryNode(name:name);created=item.id
      try next.insert([item],roots:[item.id],parent:parent,before:nil);next.selectedNodes=[item.id]
    case .rename(let id,let name):
      try Self.validateName(name);guard let item=node(id)else{throw CraftError.invalid("Pattern item no longer exists.")}
      if let asset=item.patternID {next.patterns[next.patterns.firstIndex{$0.id==asset}!].name=name}
      else{next.nodes[next.nodes.firstIndex{$0.id==id}!].name=name}
    case .move(let ids,let parent,let before):
      let roots=try topmost(ids),all=roots.reduce(into:Set<UUID>()){$0.formUnion(descendants(of:$1.id))}
      guard parent==nil || !all.contains(parent!),before==nil || !all.contains(before!)else{throw CraftError.invalid("A pattern group cannot move inside itself or before its own contents.")}
      let moving=try orderedNodes().filter{all.contains($0.id)};next.nodes.removeAll{all.contains($0.id)}
      try next.insert(moving,roots:Set(roots.map(\.id)),parent:parent,before:before)
    case .duplicate(let ids,let parent,let before):
      let roots=try topmost(ids),all=roots.reduce(into:Set<UUID>()){$0.formUnion(descendants(of:$1.id))},source=try orderedNodes().filter{all.contains($0.id)}
      let nodeIDs=Dictionary(uniqueKeysWithValues:source.map{($0.id,UUID())});var assets=[String:String](),copies=[PatternLibraryNode]()
      for item in source {
        var copy=item;copy.id=nodeIDs[item.id]!;copy.parentID=item.parentID.flatMap{nodeIDs[$0]}
        if let id=item.patternID {
          if assets[id]==nil {
            let original=patterns.first{$0.id==id}!,newID=UUID().uuidString
            next.patterns.append(try RasterPattern(name:original.name,surface:original.surface,id:newID));assets[id]=newID
          }
          copy.patternID=assets[id]
        }else if roots.contains(where:{$0.id==item.id}){copy.name += " copy"}
        copies.append(copy)
      }
      let copiedRoots=Set(roots.map{nodeIDs[$0.id]!});try next.insert(copies,roots:copiedRoots,parent:parent,before:before)
      next.selectedNodes=copiedRoots;next.activeNodeID=copies.first(where:{$0.patternID != nil})?.id
      if let active=next.activeNodeID{next.selectedID=next.node(active)?.patternID};created=copiedRoots.sorted{$0.uuidString<$1.uuidString}.first
    case .delete(let ids):
      let roots=try topmost(ids),all=roots.reduce(into:Set<UUID>()){$0.formUnion(descendants(of:$1.id))};next.nodes.removeAll{all.contains($0.id)}
      let retained=Set(next.nodes.compactMap(\.patternID));next.patterns.removeAll{!retained.contains($0.id)};next.pruneSelection()
    case .collapse(let id,let collapse):
      guard node(id)?.isGroup==true else{throw CraftError.invalid("Choose a pattern group.")}
      if collapse{next.collapsed.insert(id)}else{next.collapsed.remove(id)}
    }
    try next.validate();self=next;return created
  }
  public mutating func install(_ incoming:PatternLibraryState,into parent:UUID?=nil)throws {
    try incoming.validate();try validate();var next=self
    for asset in incoming.patterns {
      if let i=next.patterns.firstIndex(where:{$0.id==asset.id}){next.patterns[i]=asset}else{next.patterns.append(asset)}
    }
    let ids=Dictionary(uniqueKeysWithValues:incoming.nodes.map{($0.id,UUID())})
    let values=incoming.nodes.map { item -> PatternLibraryNode in
      var copy=item;copy.id=ids[item.id]!;copy.parentID=item.parentID.flatMap{ids[$0]};return copy
    }
    try next.insert(values,roots:Set(incoming.nodes.filter{$0.parentID==nil}.map{ids[$0.id]!}),parent:parent,before:nil)
    next.activeNodeID=values.last(where:{$0.patternID != nil})?.id;next.selectedNodes=Set(next.activeNodeID.map{[$0]} ?? [])
    if let active=next.activeNodeID{next.selectedID=next.node(active)?.patternID}
    try next.validate();self=next
  }
  public func subset(_ ids:Set<UUID>?)throws->Self {
    guard let ids else{return self};let roots=try topmost(ids),all=roots.reduce(into:Set<UUID>()){$0.formUnion(descendants(of:$1.id))}
    var nodes=try orderedNodes().filter{all.contains($0.id)};let rootIDs=Set(roots.map(\.id))
    for i in nodes.indices where rootIDs.contains(nodes[i].id){nodes[i].parentID=nil}
    let assets=Set(nodes.compactMap(\.patternID));let result=Self(patterns:patterns.filter{assets.contains($0.id)},nodes:nodes);try result.validate();return result
  }
}
