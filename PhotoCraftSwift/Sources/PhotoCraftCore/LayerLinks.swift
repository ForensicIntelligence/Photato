import Foundation
import CryptoKit

public enum LayerLinkCommand:Sendable {
  case link([UUID]),unlink([UUID]),enabled([UUID],Bool)
  public var label:String{switch self{case .link:"Link Layers";case .unlink:"Unlink Layers";case .enabled(_,let value):value ? "Enable Layer Links":"Disable Layer Links"}}
}
public struct LayerMoveRequest:Codable,Equatable,Sendable {
  public var layerIDs:[UUID]
  public var dx:Int,dy:Int
  public var copy:Bool?
  public init(layerIDs:[UUID],dx:Int,dy:Int,copy:Bool?=nil){self.layerIDs=layerIDs;self.dx=dx;self.dy=dy;self.copy=copy}
}
public enum LayerLinks {
  public static func identifier(document:UUID,members:Set<UUID>)->UUID {
    let value="Photato layer links\0"+document.uuidString+"\0"+members.map(\.uuidString).sorted().joined(separator:"\0")
    let bytes=Array(SHA256.hash(data:Data(value.utf8)).prefix(16))
    return UUID(uuid:(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],(bytes[6]&15)|80,bytes[7],(bytes[8]&63)|128,bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
  }
  public static func related(in document:CraftDocument,layerIDs:Set<UUID>,enabledOnly:Bool=false)->Set<UUID>{
    let groups=Set(document.layers.filter{layerIDs.contains($0.id) && (!enabledOnly || $0.linkDisabled != true)}.compactMap(\.linkID))
    return layerIDs.union(document.layers.filter{layer in layer.linkID.map{groups.contains($0)} == true && (!enabledOnly || layer.linkDisabled != true)}.map(\.id))
  }
  /// A moved group also moves its children and their enabled linked partners.
  public static func expanded(in document:CraftDocument,layerIDs:Set<UUID>)->Set<UUID>{
    let byID=Dictionary(document.layers.map{($0.id,$0)},uniquingKeysWith:{first,_ in first}),children=Dictionary(grouping:document.layers,by:{$0.parentID})
    let links=Dictionary(grouping:document.layers.filter{$0.linkID != nil && $0.linkDisabled != true},by:{$0.linkID!})
    var ids=Set<UUID>(),queue=Array(layerIDs),seenGroups=Set<UUID>()
    while let id=queue.popLast(){guard ids.insert(id).inserted else{continue};queue += (children[id] ?? []).map(\.id)
      if let layer=byID[id],layer.linkDisabled != true,let group=layer.linkID,seenGroups.insert(group).inserted{queue += (links[group] ?? []).map(\.id)}
    }
    return ids
  }
  public static func prune(in document:inout CraftDocument){
    let counts=Dictionary(grouping:document.layers.filter{$0.linkID != nil},by:{$0.linkID!}).mapValues(\.count)
    for i in document.layers.indices where document.layers[i].linkID.map{counts[$0,default:0]<2} == true{document.layers[i].linkID=nil;document.layers[i].linkDisabled=nil}
  }
  public static func independentCopies(in document:inout CraftDocument,layerIDs:Set<UUID>){
    let groups=Dictionary(grouping:document.layers.filter{layerIDs.contains($0.id) && $0.linkID != nil},by:{$0.linkID!})
    for members in groups.values{let ids=Set(members.map(\.id)),group=ids.count>1 ? identifier(document:document.id,members:ids):nil
      for i in document.layers.indices where ids.contains(document.layers[i].id){document.layers[i].linkID=group;if group==nil{document.layers[i].linkDisabled=nil}}
    }
  }
  public static func validate(_ document:CraftDocument)throws{
    guard document.layers.allSatisfy({$0.linkDisabled != true || $0.linkID != nil}) else{throw CraftError.invalid("A disabled link requires a layer-link relationship.")}
    // A class ID may occur once in a derived layer subset. It has no peer,
    // and editing/isolating helpers prune it; the stored class label is not a dangling reference.
  }
  public static func apply(_ command:LayerLinkCommand,to document:inout CraftDocument)throws {
    try Task.checkCancellation();let requested:[UUID]
    switch command{case .link(let ids),.unlink(let ids),.enabled(let ids,_):requested=ids}
    let ids=Set(requested)
    guard !ids.isEmpty,ids.count==requested.count,ids.isSubset(of:Set(document.layers.map(\.id))) else{throw CraftError.invalid("Choose distinct existing layers to change their links.")}
    var candidate=document
    switch command{
    case .link:
      guard ids.count>=2,document.layers.allSatisfy({!ids.contains($0.id) || !$0.isBackground}) else{throw CraftError.invalid("Choose at least two regular layers or groups. Convert Background first.")}
      let merged=related(in:document,layerIDs:ids),existing=Set(document.layers.filter{merged.contains($0.id)}.compactMap(\.linkID)),allLinked=document.layers.filter{merged.contains($0.id)}.allSatisfy{$0.linkID != nil}
      let group=existing.count==1 && allLinked ? existing.first!:identifier(document:document.id,members:merged)
      for i in candidate.layers.indices where merged.contains(candidate.layers[i].id){candidate.layers[i].linkID=group;if ids.contains(candidate.layers[i].id){candidate.layers[i].linkDisabled=nil}}
    case .unlink:
      for i in candidate.layers.indices where ids.contains(candidate.layers[i].id){candidate.layers[i].linkID=nil;candidate.layers[i].linkDisabled=nil}
    case .enabled(_,let enabled):
      guard document.layers.filter({ids.contains($0.id)}).allSatisfy({$0.linkID != nil}) else{throw CraftError.invalid("Choose linked layers to change temporary link participation.")}
      for i in candidate.layers.indices where ids.contains(candidate.layers[i].id){candidate.layers[i].linkDisabled=enabled ? nil:true}
    }
    prune(in:&candidate);try candidate.validate();try Task.checkCancellation();document=candidate
  }
  static func move(_ request:LayerMoveRequest,in document:inout CraftDocument)throws{
    try Task.checkCancellation();let requested=Set(request.layerIDs)
    guard !requested.isEmpty,requested.count==request.layerIDs.count,requested.isSubset(of:Set(document.layers.map(\.id))),abs(Double(request.dx))<=1_000_000,abs(Double(request.dy))<=1_000_000 else{throw CraftError.invalid("Invalid whole-layer Move targets or offsets.")}
    let ids=expanded(in:document,layerIDs:requested)
    let hierarchy=LayerHierarchyIndex(document)
    guard ids.allSatisfy({!hierarchy.effectiveProtection($0).locksPosition}) else{throw CraftError.invalid("Unlock positions on every moved layer and linked partner.")}
    if request.dx==0 && request.dy==0 && request.copy != true{return}
    var candidate=document
    var moving=ids
    if request.copy == true{try LayerDuplication.duplicate(in:&candidate,selected:ids,name:nil);moving=Set(candidate.layers.map(\.id)).subtracting(document.layers.map(\.id))}
    let original=candidate,delta=Transform2D.translation(Double(request.dx),Double(request.dy))
    for i in candidate.layers.indices where moving.contains(candidate.layers[i].id){try Task.checkCancellation();let old=original.layers[i]
      guard abs(Double(old.x)+Double(request.dx))<=1_000_000,abs(Double(old.y)+Double(request.dy))<=1_000_000 else{throw CraftError.invalid("Linked layer Move exceeds supported coordinates.")}
      candidate.layers[i].smartFilters?.transformPuppetPins(delta);candidate.layers[i].smartFilters?.transformPerspectivePlanes(delta)
      candidate.layers[i].x+=request.dx;candidate.layers[i].y+=request.dy;try candidate.layers[i].movePattern(x:request.dx,y:request.dy);try candidate.layers[i].preserveUnlinkedMask(from:old)
      if old.smartFilters?.maskProperties.linked == true{candidate.layers[i].smartFilters?.maskProperties.transform=delta*old.smartFilters!.maskProperties.transform}
      if old.vectorMask?.linked == true{candidate.layers[i].vectorMask?.path=old.vectorMask!.path.transformed(delta)}
    }
    try Task.checkCancellation();document=candidate
  }
}
extension CraftDocument {
  public var requiresLayerLinkArchive:Bool{
    layers.contains{$0.linkID != nil || $0.linkDisabled != nil} || animation?.retainedVideoSource?.layers.contains{$0.linkID != nil || $0.linkDisabled != nil} == true || videoTimeline?.retainedFrameSources?.contains{$0.layers.contains{$0.linkID != nil || $0.linkDisabled != nil}} == true
  }
}
